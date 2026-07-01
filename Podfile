platform :osx, "10.13"

source 'https://github.com/MacDownApp/cocoapods-specs.git'  # Patched libraries.
source 'https://cdn.cocoapods.org/'

project 'MacDown.xcodeproj'

inhibit_all_warnings!

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  pod 'hoedown', '~> 3.0.7', :inhibit_warnings => false
  pod 'JJPluralForm', '~> 2.1'
  pod 'LibYAML', '~> 0.1'
  pod 'M13OrderedDictionary', '~> 1.1'
  pod 'MASPreferences', '~> 1.3'

  # Locked on 0.4.x until we drop 10.8.
  pod 'PAPreferences', '~> 0.4'
end

target "MacDownTests" do
  pod 'PAPreferences', '~> 0.4'
end

target "macdown-cmd" do
  pod 'GBCli', '~> 1.1'
end

# ---------------------------------------------------------------------------
# SECURITY PATCH (Phase 4, finding 8): LibYAML 0.1.4 — CVE-2014-2525
# Heap buffer overflow in yaml_parser_scan_uri_escapes() (scanner.c): the octet
# copy writes without a preceding STRING_EXTEND, so a long run of %-escaped
# bytes in a URI/tag overflows the heap. Reachable from .md YAML front-matter
# (NSString+Lookup -> YAMLSerialization -> LibYAML). The CocoaPods 'LibYAML'
# spec is frozen at 0.1.4 (no patched release published), so we patch the
# downloaded source in place at install time. Idempotent + CI-safe.
# Canonical patch: Scripts/patches/libyaml-cve-2014-2525.patch
# Reversible: git tag pre-cve-libyaml. See docs/SECURITY-AUDIT.md finding 8.
# ---------------------------------------------------------------------------
post_install do |installer|
  scanner = File.join(installer.sandbox.root, 'LibYAML', 'src', 'scanner.c')
  if File.exist?(scanner)
    code = File.read(scanner)
    if code.include?('STRING_EXTEND(parser, *string)')
      Pod::UI.message '[security] LibYAML CVE-2014-2525 patch already present.'
    elsif code.scan('*(string->pointer++) = octet;').length == 1
      code = code.sub(
        '*(string->pointer++) = octet;',
        "/* SECURITY (CVE-2014-2525): ensure capacity before writing. */\n        if (!STRING_EXTEND(parser, *string)) return 0;\n        *(string->pointer++) = octet;"
      )
      File.chmod(0644, scanner) rescue nil
      File.write(scanner, code)
      raise '[security] LibYAML CVE-2014-2525 patch FAILED' unless code.include?('STRING_EXTEND(parser, *string)')
      Pod::UI.message '[security] Applied LibYAML CVE-2014-2525 patch (scanner.c).'
    else
      Pod::UI.warn '[security] LibYAML scanner.c anchor changed — CVE-2014-2525 patch NOT applied; review manually.'
    end
  end

  # -------------------------------------------------------------------------
  # SECURITY PATCH (Phase 4, finding 7c): LibYAML 0.1.4 — compose-time depth cap
  # yaml_parser_load_node -> load_sequence/load_mapping -> load_node recurses
  # WITHOUT any bound; deeply-nested YAML flow ("[[[[…") in .md front-matter
  # overflows the 512KB NSOperationQueue thread stack (NSString+Lookup ->
  # YAMLSerialization -> yaml_parser_load_document). Fixed by wrapping
  # load_node's dispatch with a static compose-time depth counter capped at
  # MDEDITOR_YAML_MAX_DEPTH (100). Deeper input returns a clean composer error
  # (0) instead of crashing; the counter is safe as static because
  # NSString+Lookup drives one YAML parse at a time on a dedicated queue.
  # See docs/SECURITY-AUDIT.md finding 7c. Idempotent + CI-safe.
  # -------------------------------------------------------------------------
  loader = File.join(installer.sandbox.root, 'LibYAML', 'src', 'loader.c')
  if File.exist?(loader)
    code = File.read(loader)
    if code.include?('MDEDITOR_YAML_MAX_DEPTH')
      Pod::UI.message '[security] LibYAML finding 7c depth-cap patch already present.'
    else
      original = <<~ORIG
        static int
        yaml_parser_load_node(yaml_parser_t *parser, yaml_event_t *first_event)
        {
            switch (first_event->type) {
                case YAML_ALIAS_EVENT:
                    return yaml_parser_load_alias(parser, first_event);
                case YAML_SCALAR_EVENT:
                    return yaml_parser_load_scalar(parser, first_event);
                case YAML_SEQUENCE_START_EVENT:
                    return yaml_parser_load_sequence(parser, first_event);
                case YAML_MAPPING_START_EVENT:
                    return yaml_parser_load_mapping(parser, first_event);
                default:
                    assert(0);  /* Could not happen. */
                    return 0;
            }

            return 0;
        }
      ORIG
      replacement = <<~REPL
        /* SECURITY (mdeditor Phase 4 finding 7c): document-depth cap. */
        #ifndef MDEDITOR_YAML_MAX_DEPTH
        #define MDEDITOR_YAML_MAX_DEPTH 100
        #endif
        static int
        yaml_parser_load_node(yaml_parser_t *parser, yaml_event_t *first_event)
        {
            static int _mdeditor_yaml_depth = 0;
            int _mdeditor_rc;
            if (_mdeditor_yaml_depth >= MDEDITOR_YAML_MAX_DEPTH) {
                return yaml_parser_set_composer_error(parser,
                    "YAML nesting exceeds mdeditor depth cap",
                    first_event->start_mark);
            }
            _mdeditor_yaml_depth++;
            switch (first_event->type) {
                case YAML_ALIAS_EVENT:
                    _mdeditor_rc = yaml_parser_load_alias(parser, first_event); break;
                case YAML_SCALAR_EVENT:
                    _mdeditor_rc = yaml_parser_load_scalar(parser, first_event); break;
                case YAML_SEQUENCE_START_EVENT:
                    _mdeditor_rc = yaml_parser_load_sequence(parser, first_event); break;
                case YAML_MAPPING_START_EVENT:
                    _mdeditor_rc = yaml_parser_load_mapping(parser, first_event); break;
                default:
                    assert(0);  /* Could not happen. */
                    _mdeditor_rc = 0;
            }
            _mdeditor_yaml_depth--;
            return _mdeditor_rc;
        }
      REPL
      if code.include?(original)
        code = code.sub(original, replacement)
        File.chmod(0644, loader) rescue nil
        File.write(loader, code)
        raise '[security] LibYAML finding 7c patch FAILED' unless code.include?('MDEDITOR_YAML_MAX_DEPTH')
        Pod::UI.message '[security] Applied LibYAML finding 7c depth-cap patch (loader.c).'
      else
        Pod::UI.warn '[security] LibYAML loader.c anchor changed — finding 7c patch NOT applied; review manually.'
      end
    end
  end
end
