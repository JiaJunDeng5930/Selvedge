use std::fmt;

use reqwest::Url;

// @constraint selvedge.client.redaction HTTP diagnostics expose sanitized URLs without credentials, query strings, or fragments.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SanitizedUrl(String);

impl SanitizedUrl {
    // @behavior selvedge.client.redaction.as_str Sanitized URLs expose their redacted text as a string slice.
    pub(crate) fn as_str(&self) -> &str {
        self.0.as_str()
    }

    // @behavior selvedge.client.redaction.into_string Sanitized URLs can be returned to callers as owned strings.
    pub(crate) fn into_string(self) -> String {
        self.0
    }
}

// @behavior selvedge.client.redaction.display Sanitized URL display text is the sanitized URL string.
impl fmt::Display for SanitizedUrl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

// @behavior selvedge.client.redaction.sanitize_url Raw URL text is converted into a sanitized URL for HTTP logs and errors.
pub(crate) fn sanitize_url(raw: &str) -> SanitizedUrl {
    // @behavior selvedge.client.redaction.invalid Invalid URL text is represented as <invalid-url> in HTTP diagnostics.
    let Ok(parsed) = Url::parse(raw) else {
        return SanitizedUrl("<invalid-url>".to_owned());
    };

    sanitize_parsed_url(&parsed)
}

// @constraint selvedge.client.redaction.parts Sanitized URLs retain scheme, host, port, and path while removing credentials, query strings, and fragments.
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

// @behavior selvedge.client.redaction.error_text HTTP error text replaces known and embedded URLs with sanitized forms before callers receive the error.
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

        // @constraint selvedge.client.redaction.embedded Embedded lowercase http and https URLs in transport error messages are scrubbed before logging or returning the message.
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
        (Some(_), Some(https)) => Some((https, "https://")),
        (Some(http), None) => Some((http, "http://")),
        (None, Some(https)) => Some((https, "https://")),
        (None, None) => None,
    }
}

// @constraint selvedge.client.redaction.embedded.delimiter Embedded URL scanning stops at whitespace, quote, bracket, parenthesis, or angle-bracket delimiters.
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
