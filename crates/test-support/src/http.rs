use std::net::SocketAddr;

use axum::Router;
use tokio::{net::TcpListener, task::JoinHandle};

pub struct HttpTestServer {
    addr: SocketAddr,
    handle: JoinHandle<()>,
}

impl HttpTestServer {
    pub fn addr(&self) -> SocketAddr {
        self.addr
    }

    pub fn port(&self) -> u16 {
        self.addr.port()
    }

    pub fn base_url(&self) -> String {
        format!("http://{}", self.addr)
    }

    pub fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url(), path)
    }
}

impl Drop for HttpTestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

pub async fn spawn_axum_server(router: Router) -> HttpTestServer {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        axum::serve(listener, router).await.expect("serve test app");
    });

    HttpTestServer { addr, handle }
}

pub async fn spawn_http_server(router: Router) -> HttpTestServer {
    spawn_axum_server(router).await
}

pub struct HeldLoopbackPort {
    listener: std::net::TcpListener,
    addr: SocketAddr,
}

impl HeldLoopbackPort {
    pub fn addr(&self) -> SocketAddr {
        self.addr
    }

    pub fn port(&self) -> u16 {
        self.listener
            .local_addr()
            .expect("held loopback addr")
            .port()
    }
}

pub fn hold_loopback_port() -> HeldLoopbackPort {
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("bind held loopback port");
    let addr = listener.local_addr().expect("held loopback addr");
    HeldLoopbackPort { listener, addr }
}

pub fn released_loopback_port() -> u16 {
    let held = hold_loopback_port();
    let port = held.port();
    drop(held);
    port
}
