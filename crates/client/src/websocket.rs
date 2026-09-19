use std::{
    future::Future,
    io,
    pin::Pin,
    sync::{Arc, Mutex},
    task::{Context, Poll},
    time::Duration,
};

use futures_util::{
    SinkExt, StreamExt,
    stream::{SplitSink, SplitStream},
};
use http::{HeaderMap, header::USER_AGENT};
use tokio::{
    io::{AsyncRead, AsyncWrite, ReadBuf},
    net::TcpStream,
    sync::Mutex as AsyncMutex,
    time::Instant,
};
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_tungstenite::{
    Connector, MaybeTlsStream, WebSocketStream, client_async_tls_with_config,
    tungstenite::{self, Message, client::IntoClientRequest, protocol::WebSocketConfig},
};

use crate::{
    HttpError, HttpStatusError, build_error, config_resolution::resolve_call_config,
    redaction::sanitize_url,
};

const MAX_MESSAGE_BYTES: usize = 4 * 1024 * 1024;
type Socket = WebSocketStream<MaybeTlsStream<ReadActivity>>;
type SharedSink = Arc<AsyncMutex<SplitSink<Socket, Message>>>;

pub struct WebSocketRequest {
    pub url: String,
    pub headers: HeaderMap,
    pub timeout: Option<Duration>,
}

pub struct WebSocketConnection {
    pub headers: HeaderMap,
    socket: Socket,
    budget: Budget,
    idle_timeout: Option<Duration>,
    activity: Arc<Mutex<Instant>>,
}

pub struct WebSocketSender {
    sink: SharedSink,
    budget: Budget,
}

pub struct WebSocketReceiver {
    stream: SplitStream<Socket>,
    sink: SharedSink,
    budget: Budget,
    idle_timeout: Option<Duration>,
    finished: bool,
    activity: Arc<Mutex<Instant>>,
}

impl WebSocketConnection {
    pub fn split(self) -> (WebSocketSender, WebSocketReceiver) {
        let (sink, stream) = self.socket.split();
        let sink = Arc::new(AsyncMutex::new(sink));
        (
            WebSocketSender {
                sink: sink.clone(),
                budget: self.budget.clone(),
            },
            WebSocketReceiver {
                stream,
                sink,
                budget: self.budget,
                idle_timeout: self.idle_timeout,
                finished: false,
                activity: self.activity,
            },
        )
    }
}

impl WebSocketSender {
    pub async fn send_text(&mut self, text: String) -> Result<(), HttpError> {
        if text.len() > MAX_MESSAGE_BYTES {
            return Err(HttpError::ResponseTooLarge {
                limit_bytes: MAX_MESSAGE_BYTES,
            });
        }
        self.budget
            .wait(None, async {
                self.sink
                    .lock()
                    .await
                    .send(Message::Text(text.into()))
                    .await
                    .map_err(map_socket_error)
            })
            .await
    }

    /// Send a close frame. Continue polling the receiver to finish the peer handshake.
    pub async fn close(&mut self) -> Result<(), HttpError> {
        self.budget
            .wait(None, async {
                self.sink
                    .lock()
                    .await
                    .close()
                    .await
                    .map_err(map_socket_error)
            })
            .await
    }
}

impl WebSocketReceiver {
    pub async fn next_text(&mut self) -> Result<Option<String>, HttpError> {
        if self.finished {
            return Ok(None);
        }
        let result = self.receive_text().await;
        if !matches!(result, Ok(Some(_))) {
            self.finished = true;
        }
        result
    }

    async fn receive_text(&mut self) -> Result<Option<String>, HttpError> {
        loop {
            let message = self
                .budget
                .wait(
                    None,
                    next_frame(&mut self.stream, &self.activity, self.idle_timeout),
                )
                .await?;
            match message {
                Some(Message::Text(text)) => return Ok(Some(text.to_string())),
                Some(Message::Ping(_)) => {
                    // Tungstenite queues the automatic pong while reading; flush it even
                    // when the application has no outgoing commands.
                    self.budget
                        .wait(None, async {
                            self.sink
                                .lock()
                                .await
                                .flush()
                                .await
                                .map_err(map_socket_error)
                        })
                        .await?;
                }
                Some(Message::Close(_)) => {
                    self.budget
                        .wait(None, async {
                            match self.sink.lock().await.flush().await {
                                Ok(()) | Err(tungstenite::Error::ConnectionClosed) => Ok(()),
                                Err(error) => Err(map_socket_error(error)),
                            }
                        })
                        .await?;
                    return Ok(None);
                }
                None => return Ok(None),
                Some(Message::Binary(_)) => {
                    return Err(HttpError::Io {
                        reason: "received binary message on a text WebSocket".into(),
                    });
                }
                Some(Message::Pong(_) | Message::Frame(_)) => {}
            }
        }
    }
}

pub async fn connect_websocket(
    request: WebSocketRequest,
) -> Result<WebSocketConnection, HttpError> {
    let config = resolve_call_config(request.timeout)?;
    let url = url::Url::parse(&request.url).map_err(|_| build_error("invalid WebSocket URL"))?;
    if !matches!(url.scheme(), "ws" | "wss")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(build_error(
            "WebSocket URL must use ws or wss and contain no credentials or fragment",
        ));
    }
    let host = url
        .host_str()
        .ok_or_else(|| build_error("WebSocket URL has no host"))?;
    let port = url
        .port_or_known_default()
        .ok_or_else(|| build_error("WebSocket URL has no port"))?;
    let mut handshake = request
        .url
        .as_str()
        .into_client_request()
        .map_err(|_| build_error("invalid WebSocket handshake request"))?;
    for (name, value) in &request.headers {
        if matches!(
            name.as_str(),
            "host" | "connection" | "upgrade" | "sec-websocket-key" | "sec-websocket-version"
        ) {
            return Err(build_error(
                "caller cannot override WebSocket handshake headers",
            ));
        }
        handshake.headers_mut().append(name, value.clone());
    }
    if !handshake.headers().contains_key(USER_AGENT)
        && let Some(user_agent) = config.user_agent
    {
        handshake.headers_mut().insert(
            USER_AGENT,
            user_agent
                .parse()
                .map_err(|_| build_error("invalid network.user_agent"))?,
        );
    }
    let connector = if url.scheme() == "wss" {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        if let Some(path) = config.ca_bundle_path {
            let pem = tokio::fs::read(path)
                .await
                .map_err(|_| build_error("failed to read network.ca_bundle_path"))?;
            let certificates = rustls_pemfile::certs(&mut pem.as_slice())
                .collect::<Result<Vec<_>, _>>()
                .map_err(|_| build_error("invalid network.ca_bundle_path PEM"))?;
            if certificates.is_empty() {
                return Err(build_error(
                    "network.ca_bundle_path contains no certificates",
                ));
            }
            for cert in certificates {
                roots
                    .add(cert)
                    .map_err(|_| build_error("invalid CA certificate"))?;
            }
        }
        let tls = ClientConfig::builder_with_provider(Arc::new(
            tokio_rustls::rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .map_err(|_| build_error("invalid TLS protocol configuration"))?
        .with_root_certificates(roots)
        .with_no_client_auth();
        Some(Connector::Rustls(Arc::new(tls)))
    } else {
        None
    };
    let budget = Budget::new(config.request_timeout);
    let activity = Arc::new(Mutex::new(Instant::now()));
    let connect = async {
        let stream =
            TcpStream::connect((host, port))
                .await
                .map_err(|error| HttpError::Connect {
                    reason: error.to_string(),
                })?;
        let websocket_config = WebSocketConfig::default()
            .max_message_size(Some(MAX_MESSAGE_BYTES))
            .max_frame_size(Some(MAX_MESSAGE_BYTES));
        client_async_tls_with_config(
            handshake,
            ReadActivity {
                stream,
                activity: activity.clone(),
            },
            Some(websocket_config),
            connector,
        )
        .await
        .map_err(|error| {
            if let tungstenite::Error::Http(response) = error {
                HttpError::Status(HttpStatusError {
                    url: sanitize_url(&request.url).to_string(),
                    status: response.status(),
                    headers: response.headers().clone(),
                    body: response.into_body().unwrap_or_default().into(),
                })
            } else {
                map_socket_error(error)
            }
        })
    };
    let (socket, response) = budget.wait(config.connect_timeout, connect).await?;
    Ok(WebSocketConnection {
        headers: response.into_parts().0.headers,
        socket,
        budget,
        idle_timeout: config.stream_idle_timeout,
        activity,
    })
}

fn map_socket_error(error: tungstenite::Error) -> HttpError {
    match error {
        tungstenite::Error::Capacity(_) => HttpError::ResponseTooLarge {
            limit_bytes: MAX_MESSAGE_BYTES,
        },
        tungstenite::Error::Io(ref error)
            if error
                .get_ref()
                .is_some_and(|source| source.is::<tokio_rustls::rustls::Error>()) =>
        {
            HttpError::Tls {
                reason: "WebSocket TLS validation failed".into(),
            }
        }
        tungstenite::Error::Tls(error) => HttpError::Tls {
            reason: error.to_string(),
        },
        // Protocol and HTTP errors can contain peer-controlled payloads. Avoid
        // reflecting request headers or response text in transport diagnostics.
        _ => HttpError::Io {
            reason: "WebSocket transport failed".into(),
        },
    }
}

#[derive(Clone)]
struct Budget(Arc<Mutex<BudgetState>>);
struct BudgetState {
    remaining: Option<Duration>,
    active: usize,
    since: Instant,
}
struct WaitGuard(Budget);

impl Budget {
    fn new(remaining: Option<Duration>) -> Self {
        Self(Arc::new(Mutex::new(BudgetState {
            remaining,
            active: 0,
            since: Instant::now(),
        })))
    }

    async fn wait<T>(
        &self,
        limit: Option<Duration>,
        future: impl Future<Output = Result<T, HttpError>>,
    ) -> Result<T, HttpError> {
        let remaining = {
            let mut state = self.0.lock().unwrap_or_else(|error| error.into_inner());
            if state.active == 0 {
                state.since = Instant::now();
            }
            state.active += 1;
            state
                .remaining
                .map(|remaining| remaining.saturating_sub(state.since.elapsed()))
        };
        let _guard = WaitGuard(self.clone());
        let timeout = match (remaining, limit) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        };
        match timeout {
            Some(timeout) => tokio::time::timeout(timeout, future)
                .await
                .map_err(|_| HttpError::Timeout)?,
            None => future.await,
        }
    }
}

impl Drop for WaitGuard {
    fn drop(&mut self) {
        let mut state = self.0.0.lock().unwrap_or_else(|error| error.into_inner());
        state.active -= 1;
        // Overlapping reads and writes consume wall time once, while caller-side
        // pauses and cancellation do not leave a running timer behind.
        if state.active == 0 {
            state.remaining = state
                .remaining
                .map(|remaining| remaining.saturating_sub(state.since.elapsed()));
        }
    }
}

// Observe wire progress below Tungstenite so partial frames reset idle waits.
struct ReadActivity {
    stream: TcpStream,
    activity: Arc<Mutex<Instant>>,
}
impl AsyncRead for ReadActivity {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let before = buffer.filled().len();
        let result = Pin::new(&mut self.stream).poll_read(cx, buffer);
        if matches!(result, Poll::Ready(Ok(()))) && buffer.filled().len() > before {
            *self
                .activity
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Instant::now();
        }
        result
    }
}
impl AsyncWrite for ReadActivity {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.stream).poll_write(cx, buffer)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_shutdown(cx)
    }
}

async fn next_frame(
    stream: &mut SplitStream<Socket>,
    activity: &Arc<Mutex<Instant>>,
    idle: Option<Duration>,
) -> Result<Option<Message>, HttpError> {
    let mut read = Box::pin(stream.next());
    let Some(idle) = idle else {
        return read.await.transpose().map_err(map_socket_error);
    };
    let mut observed = Instant::now();
    loop {
        match tokio::time::timeout(idle.saturating_sub(observed.elapsed()), &mut read).await {
            Ok(message) => return message.transpose().map_err(map_socket_error),
            Err(_) => {
                let latest = *activity.lock().unwrap_or_else(|error| error.into_inner());
                if latest > observed {
                    observed = latest;
                } else {
                    return Err(HttpError::Timeout);
                }
            }
        }
    }
}
