#![no_main]

use libfuzzer_sys::fuzz_target;

/// Perform sanity checks on parser events.
///
/// This fuzzer validates that:
/// - Event ranges don't overlap (except for special caption case)
/// - All ranges are valid unicode boundaries
/// - All container start events have matching end events
/// - Only whitespace remains after the last event
fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // Attributes are outside events, so whitespace checking needs special handling
        let whitelist_whitespace = s.contains('{') && s.contains('}');
        
        let mut open = Vec::new();
        let mut last = (jotup::Event::Str("".into()), 0..0);
        
        for (event, range) in jotup::Parser::new(s).into_offset_iter() {
            // Verify no overlap or out of order events
            assert!(
                last.1.end <= range.start
                // Caption event is before table rows but src is after
                || (
                    matches!(
                        last.0,
                        jotup::Event::Start(jotup::Container::Caption, ..)
                        | jotup::Event::End
                    )
                    && range.end <= last.1.start
                ),
                "Event range overlap: {} > {} {:?} {:?}",
                last.1.end,
                range.start,
                last.0,
                event
            );
            
            last = (event.clone(), range.clone());
            
            // Verify range is valid unicode - does not cross char boundary
            let _ = &s[range];
            
            // Track container nesting
            match event {
                jotup::Event::Start(c, ..) => open.push(c.clone()),
                jotup::Event::End => {
                    if open.is_empty() {
                        panic!("End event without matching Start");
                    }
                    open.pop();
                }
                _ => {}
            }
        }
        
        // Verify all containers were closed
        assert_eq!(open, &[], "Unclosed containers: {:?}", open);
        
        // Verify only whitespace after last event
        assert!(
            whitelist_whitespace || s[last.1.end..].chars().all(char::is_whitespace),
            "Non-whitespace after last event: {:?}",
            &s[last.1.end..],
        );
    }
});
