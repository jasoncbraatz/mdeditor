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
end
