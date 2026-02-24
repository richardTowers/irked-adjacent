# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`irked-adjacent` is a research project exploring AI agents building content management systems (CMSs) across different programming languages. The same CMS is implemented in multiple languages to compare how well agents perform in each ecosystem.

## Repository Structure

- `tickets/` - Markdown feature specifications for the CMSs (mostly AI-authored, human-edited)
- `acceptance-tests/` - End-to-end tests that all implementations must pass (authored against Rails, applied to all)
- `ruby-rails/` - Primary implementation: Ruby on Rails
- `rust-actix/` - Secondary implementation: Rust

## Development Workflow

Features are specified in `tickets/`, then implemented first in Rails, then translated to Rust. Acceptance tests in `acceptance-tests/` define the contract all implementations must satisfy.

## Key Context

- The project author is confident in Ruby on Rails but is learning Rust, so the Rails implementation leads and the Rust implementation follows
- The Rails implementation should use standard Rails conventions (Bundler, RSpec, Rubocop)
- The Rust implementation uses Actix Web and idiomatic Rust tooling (Cargo, clippy)
- Accessibility and security are explicit concerns — pay close attention to both
