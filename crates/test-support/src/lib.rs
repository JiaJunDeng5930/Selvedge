#![doc = include_str!("../README.md")]
//! @behavior selvedge.testsupport Shared test support provides reusable fixtures for workspace tests without owning product behavior.

// @behavior selvedge.testsupport.process_module Process fixture helpers are always available to integration tests.
pub mod process;

#[cfg(feature = "chatgpt-auth")]
// @behavior selvedge.testsupport.chatgpt_auth_module ChatGPT auth fixture helpers are available behind the chatgpt-auth feature.
pub mod chatgpt_auth;

#[cfg(feature = "config")]
// @behavior selvedge.testsupport.config_module Config fixture helpers are available behind the config feature.
pub mod config;

#[cfg(feature = "db-fixtures")]
// @behavior selvedge.testsupport.db_module Database fixture helpers are available behind the db-fixtures feature.
pub mod db;

#[cfg(feature = "http")]
// @behavior selvedge.testsupport.http_module HTTP fixture helpers are available behind the http feature.
pub mod http;

#[cfg(feature = "local-transport")]
// @behavior selvedge.testsupport.local_transport_module Local transport fixture helpers are available behind the local-transport feature.
pub mod local_transport;
