use std::{sync::Mutex, time::Duration};

use reqwest::{Certificate, Client};

use crate::{HttpError, build_error, config_resolution::ResolvedCallConfig, run_blocking};

#[derive(PartialEq, Eq)]
struct TransportSettings {
    connect_timeout: Option<Duration>,
    ca_bundle: Option<Vec<u8>>,
}

struct CachedTransport {
    settings: TransportSettings,
    client: Client,
}

// Retain only the most recent configuration. In-flight calls own client clones,
// so replacing the cache neither changes their trust roots nor cancels their work.
static RECENT_TRANSPORT: Mutex<Option<CachedTransport>> = Mutex::new(None);

pub(crate) struct RequestTransport<'a> {
    config: &'a ResolvedCallConfig,
    http: Option<Client>,
    https: Option<Client>,
}

impl<'a> RequestTransport<'a> {
    pub(crate) fn new(config: &'a ResolvedCallConfig) -> Self {
        Self {
            config,
            http: None,
            https: None,
        }
    }

    pub(crate) async fn client(&mut self, uses_tls: bool) -> Result<Client, HttpError> {
        let slot = if uses_tls {
            &mut self.https
        } else {
            &mut self.http
        };
        if let Some(client) = slot {
            return Ok(client.clone());
        }

        // Read actual contents once at this call's first HTTPS hop. File replacement
        // at the same path affects the next call without rebuilding on every redirect.
        let ca_bundle = if uses_tls && let Some(path) = &self.config.ca_bundle_path {
            Some(tokio::fs::read(path).await.map_err(|error| {
                build_error(format!(
                    "failed to read network.ca_bundle_path {}: {error}",
                    path.display()
                ))
            })?)
        } else {
            None
        };
        let settings = TransportSettings {
            connect_timeout: self.config.connect_timeout,
            ca_bundle,
        };
        let client = run_blocking(move || cached_client(settings)).await?;
        *slot = Some(client.clone());
        Ok(client)
    }
}

fn cached_client(settings: TransportSettings) -> Result<Client, HttpError> {
    let mut cache = RECENT_TRANSPORT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(cached) = &*cache
        && cached.settings == settings
    {
        return Ok(cached.client.clone());
    }

    let mut builder = Client::builder()
        .retry(reqwest::retry::never())
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy();
    if let Some(timeout) = settings.connect_timeout {
        builder = builder.connect_timeout(timeout);
    }
    if let Some(bundle) = &settings.ca_bundle {
        for certificate in parse_certificates(bundle)? {
            builder = builder.add_root_certificate(certificate);
        }
    }
    let client = builder
        .build()
        .map_err(|error| build_error(format!("failed to build http client: {error}")))?;
    *cache = Some(CachedTransport {
        settings,
        client: client.clone(),
    });
    Ok(client)
}

fn parse_certificates(bundle: &[u8]) -> Result<Vec<Certificate>, HttpError> {
    let mut reader = bundle;
    let certificates = rustls_pemfile::certs(&mut reader)
        .map(|parsed| {
            let parsed = parsed.map_err(|error| {
                build_error(format!("failed to parse pem certificate: {error}"))
            })?;
            Certificate::from_der(parsed.as_ref())
                .map_err(|error| build_error(format!("failed to load pem certificate: {error}")))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if certificates.is_empty() {
        return Err(build_error("ca bundle did not contain any certificates"));
    }
    Ok(certificates)
}
