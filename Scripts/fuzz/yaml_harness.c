/* yaml_harness.c — ASan/UBSan harness for LibYAML 0.1.4 (the .md YAML
 * front-matter parse path). Mirrors Dependency/YAML-framework/YAMLSerialization.m:
 * yaml_parser_initialize -> set_input_string -> yaml_parser_load loop ->
 * yaml_document_delete. Exercises the scanner, including
 * yaml_parser_scan_uri_escapes (CVE-2014-2525 heap overflow path) when the
 * input contains %-escaped URI/tag bytes.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <yaml.h>

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s <file.yaml>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0) n = 0;
    unsigned char *buf = (unsigned char *)malloc((size_t)n + 1);
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);

    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser)) { free(buf); return 3; }
    yaml_parser_set_input_string(&parser, buf, got);

    int done = 0;
    while (!done) {
        yaml_document_t document;
        if (!yaml_parser_load(&parser, &document)) {
            /* parse error is a clean, expected outcome for adversarial input */
            break;
        }
        done = !yaml_document_get_root_node(&document);
        yaml_document_delete(&document);
    }

    yaml_parser_delete(&parser);
    free(buf);
    return 0;
}
