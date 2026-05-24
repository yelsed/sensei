use zed_extension_api as zed;

struct SenseiExtension;

impl zed::Extension for SenseiExtension {
    fn new() -> Self {
        SenseiExtension
    }
}

zed::register_extension!(SenseiExtension);
