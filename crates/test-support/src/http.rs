use std::net::SocketAddr;

use axum::Router;
use tokio::{net::TcpListener, task::JoinHandle};

// @behavior selvedge.testsupport.http Axum test servers bind an ephemeral loopback port and abort the server task when dropped.
pub struct HttpTestServer {
    addr: SocketAddr,
    handle: JoinHandle<()>,
}

impl HttpTestServer {
    // @behavior selvedge.testsupport.http.addr Tests can inspect the bound loopback address for direct connection assertions.
    pub fn addr(&self) -> SocketAddr {
        self.addr
    }

    // @behavior selvedge.testsupport.http.port Tests can inspect the bound loopback port for protocol-specific clients.
    pub fn port(&self) -> u16 {
        self.addr.port()
    }

    // @behavior selvedge.testsupport.http.base_url Tests can build endpoint URLs from the bound loopback address.
    pub fn base_url(&self) -> String {
        format!("http://{}", self.addr)
    }

    // @behavior selvedge.testsupport.http.url Tests can build endpoint URLs by appending a caller-provided path.
    pub fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url(), path)
    }
}

impl Drop for HttpTestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

// @behavior selvedge.testsupport.http.spawn_axum Tests can spawn an Axum router on an ephemeral loopback port.
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

// @behavior selvedge.testsupport.http.spawn_http Legacy HTTP helper name preserves existing test call sites during migration.
pub async fn spawn_http_server(router: Router) -> HttpTestServer {
    spawn_axum_server(router).await
}

// @behavior selvedge.testsupport.http.held_port Held loopback ports keep their listener open for bind-failure tests.
pub struct HeldLoopbackPort {
    listener: std::net::TcpListener,
    addr: SocketAddr,
}

impl HeldLoopbackPort {
    // @behavior selvedge.testsupport.http.held_addr Tests can inspect the held loopback address while the listener remains open.
    pub fn addr(&self) -> SocketAddr {
        self.addr
    }

    // @behavior selvedge.testsupport.http.held_port_value Tests can inspect the held loopback port while the listener remains open.
    pub fn port(&self) -> u16 {
        self.listener
            .local_addr()
            .expect("held loopback addr")
            .port()
    }
}

// @behavior selvedge.testsupport.http.hold_port Tests can hold an ephemeral loopback port open for bind-failure scenarios.
pub fn hold_loopback_port() -> HeldLoopbackPort {
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("bind held loopback port");
    let addr = listener.local_addr().expect("held loopback addr");
    HeldLoopbackPort { listener, addr }
}

// @behavior selvedge.testsupport.http.released_port Tests can obtain a loopback port number after releasing its listener.
pub fn released_loopback_port() -> u16 {
    let held = hold_loopback_port();
    let port = held.port();
    drop(held);
    port
}
