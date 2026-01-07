#![no_main]

use html5ever::tendril;
use html5ever::tendril::TendrilSink;
use html5ever::tokenizer;
use html5ever::tree_builder;
use jotup::RenderExt;
use libfuzzer_sys::fuzz_target;

/// Validate that rendered HTML output is well-formed.
///
/// This fuzzer:
/// - Renders djot input to HTML
/// - Validates HTML using html5ever parser
/// - Checks for unexpected HTML errors (with whitelist)
fuzz_target!(|data: &[u8]| {
    // Skip inputs with null bytes
    if data.iter().any(|i| *i == 0) {
        return;
    }
    
    if let Ok(s) = std::str::from_utf8(data) {
        // Skip raw HTML blocks as they can contain arbitrary HTML
        if !s.contains("=html") {
            let p = jotup::Parser::new(s);
            let mut html = "<!DOCTYPE html>\n".to_string();
            jotup::html::Renderer::default()
                .with_fmt_writer(&mut html)
                .render_events(p)
                .unwrap();
            validate_html(&html);
        }
    }
});

fn validate_html(html: &str) {
    html5ever::parse_document(
        Dom {
            names: Vec::new(),
        },
        html5ever::ParseOpts {
            tokenizer: tokenizer::TokenizerOpts {
                exact_errors: true,
                ..tokenizer::TokenizerOpts::default()
            },
            tree_builder: tree_builder::TreeBuilderOpts {
                exact_errors: true,
                scripting_enabled: false,
                ..tree_builder::TreeBuilderOpts::default()
            },
        },
    )
    .from_utf8()
    .read_from(&mut std::io::Cursor::new(html))
    .unwrap();
}

struct Dom {
    names: Vec<html5ever::QualName>,
}

impl tree_builder::TreeSink for Dom {
    type Handle = usize;
    type Output = Self;

    fn get_document(&mut self) -> usize {
        0
    }

    fn finish(self) -> Self {
        self
    }

    fn same_node(&self, x: &usize, y: &usize) -> bool {
        x == y
    }

    fn elem_name(&self, i: &usize) -> html5ever::ExpandedName {
        self.names[i - 1].expanded()
    }

    fn create_element(
        &mut self,
        name: html5ever::QualName,
        _: Vec<html5ever::Attribute>,
        _: tree_builder::ElementFlags,
    ) -> usize {
        self.names.push(name);
        self.names.len()
    }

    fn parse_error(&mut self, msg: std::borrow::Cow<'static, str>) {
        // Whitelist of acceptable HTML errors that can occur with valid djot input
        let whitelist = &[
            "Bad character",       // bad characters in input will pass through
            "Duplicate attribute", // djot is case-sensitive while html is not
            // tags may be nested incorrectly, e.g. <a> within <a>
            "Unexpected token Tag",
            "Found special tag while closing generic tag",
            "Formatting element not current node",
            "Formatting element not open",
        ];
        
        if !whitelist.iter().any(|e| msg.starts_with(e)) {
            panic!("HTML validation error: {}", msg);
        }
    }

    fn set_quirks_mode(&mut self, _: tree_builder::QuirksMode) {}

    fn set_current_line(&mut self, _: u64) {}

    fn append(&mut self, _: &usize, _: tree_builder::NodeOrText<usize>) {}
    
    fn append_before_sibling(&mut self, _: &usize, _: tree_builder::NodeOrText<usize>) {}
    
    fn append_based_on_parent_node(
        &mut self,
        _: &usize,
        _: &usize,
        _: tree_builder::NodeOrText<usize>,
    ) {
    }
    
    fn append_doctype_to_document(
        &mut self,
        _: tendril::StrTendril,
        _: tendril::StrTendril,
        _: tendril::StrTendril,
    ) {
    }
    
    fn remove_from_parent(&mut self, _: &usize) {}
    
    fn reparent_children(&mut self, _: &usize, _: &usize) {}

    fn mark_script_already_started(&mut self, _: &usize) {}

    fn add_attrs_if_missing(&mut self, _: &usize, _: Vec<html5ever::Attribute>) {
        panic!("Unexpected call to add_attrs_if_missing");
    }

    fn create_pi(&mut self, _: tendril::StrTendril, _: tendril::StrTendril) -> usize {
        panic!("Unexpected call to create_pi")
    }

    fn get_template_contents(&mut self, _: &usize) -> usize {
        panic!("Unexpected call to get_template_contents");
    }

    fn create_comment(&mut self, _: tendril::StrTendril) -> usize {
        panic!("Unexpected call to create_comment")
    }
}
