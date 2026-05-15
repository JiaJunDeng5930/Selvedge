use std::sync::{Arc, OnceLock};

use bytes::Bytes;
use rcgen::generate_simple_self_signed;
pub use selvedge_test_support::http::spawn_http_server;
pub use selvedge_test_support::process::{assert_child_success, child_mode, run_child};
use tempfile::TempDir;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    task::JoinHandle,
};
use tokio_rustls::{
    TlsAcceptor,
    rustls::{
        self,
        pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer},
    },
};

pub async fn init_client_test() -> TempDir {
    selvedge_test_support::config::init_test_home(
        r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "debug"
"#,
    )
}

pub struct HttpsServer {
    pub url: String,
    pub ca_cert_pem: String,
    handle: JoinHandle<()>,
}

impl Drop for HttpsServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

pub async fn spawn_https_server(status: http::StatusCode, body: Bytes) -> HttpsServer {
    install_rustls_provider();
    let certificate = generate_simple_self_signed(vec!["localhost".to_owned()])
        .expect("generate self-signed certificate");
    let cert_der: CertificateDer<'static> = certificate.cert.der().clone();
    let key_der = PrivateKeyDer::from(PrivatePkcs8KeyDer::from(
        certificate.signing_key.serialize_der(),
    ));
    let ca_cert_pem = certificate.cert.pem();
    let tls_config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![cert_der], key_der)
        .expect("server tls config");
    let acceptor = TlsAcceptor::from(Arc::new(tls_config));
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind tls test server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        loop {
            let (socket, _) = listener.accept().await.expect("accept tls socket");
            let acceptor = acceptor.clone();
            let body = body.clone();

            tokio::spawn(async move {
                let mut tls_stream = acceptor.accept(socket).await.expect("tls accept");
                let mut buffer = vec![0; 4096];
                let _ = tls_stream.read(&mut buffer).await.expect("read request");
                let response = format!(
                    "HTTP/1.1 {} {}\r\ncontent-length: {}\r\n\r\n",
                    status.as_u16(),
                    status.canonical_reason().unwrap_or("OK"),
                    body.len()
                );

                tls_stream
                    .write_all(response.as_bytes())
                    .await
                    .expect("write response head");
                tls_stream
                    .write_all(&body)
                    .await
                    .expect("write response body");
                tls_stream.shutdown().await.expect("shutdown tls stream");
            });
        }
    });

    HttpsServer {
        url: format!("https://localhost:{}/", addr.port()),
        ca_cert_pem,
        handle,
    }
}

fn install_rustls_provider() {
    static INSTALLED: OnceLock<()> = OnceLock::new();

    INSTALLED.get_or_init(|| {
        rustls::crypto::ring::default_provider()
            .install_default()
            .expect("install rustls crypto provider");
    });
}
