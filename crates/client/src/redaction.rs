use std::fmt;

use reqwest::Url;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SanitizedUrl(String);

impl SanitizedUrl {
    pub(crate) fn as_str(&self) -> &str {
        self.0.as_str()
    }

    pub(crate) fn into_string(self) -> String {
        self.0
    }
}

impl fmt::Display for SanitizedUrl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

pub(crate) fn sanitize_url(raw: &str) -> SanitizedUrl {
    let Ok(parsed) = Url::parse(raw) else {
        return SanitizedUrl("<invalid-url>".to_owned());
    };

    sanitize_parsed_url(&parsed)
}

pub(crate) fn sanitize_parsed_url(url: &Url) -> SanitizedUrl {
    let mut parsed = url.clone();

    if !parsed.username().is_empty() {
        let _ = parsed.set_username("");
    }

    if parsed.password().is_some() {
        let _ = parsed.set_password(None);
    }

    parsed.set_query(None);
    parsed.set_fragment(None);

    SanitizedUrl(parsed.to_string())
}

pub(crate) fn sanitize_error_text(text: &str, known_urls: &[&str]) -> String {
    let mut sanitized = text.to_owned();

    for raw_url in known_urls {
        sanitized = sanitized.replace(raw_url, sanitize_url(raw_url).as_str());
    }

    scrub_embedded_urls(&sanitized)
}

fn scrub_embedded_urls(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut index = 0_usize;

    while index < text.len() {
        let remainder = &text[index..];
        let Some((offset, scheme)) = find_next_scheme(remainder) else {
            output.push_str(remainder);
            break;
        };

        let absolute_start = index + offset;
        output.push_str(&text[index..absolute_start]);
        let absolute_end = scan_url_end(text, absolute_start + scheme.len());
        let candidate = &text[absolute_start..absolute_end];
        output.push_str(sanitize_url(candidate).as_str());
        index = absolute_end;
    }

    output
}

fn find_next_scheme(text: &str) -> Option<(usize, &'static str)> {
    let http = text.find("http://");
    let https = text.find("https://");

    match (http, https) {
        (Some(http), Some(https)) if http <= https => Some((http, "http://")),
        (Some(http), Some(_)) => Some((http, "http://")),
        (Some(http), None) => Some((http, "http://")),
        (None, Some(https)) => Some((https, "https://")),
        (None, None) => None,
    }
}

fn scan_url_end(text: &str, mut index: usize) -> usize {
    while index < text.len() {
        let byte = text.as_bytes()[index];

        if byte.is_ascii_whitespace() || matches!(byte, b'"' | b'\'' | b')' | b']' | b'>') {
            break;
        }

        index += 1;
    }

    index
}
