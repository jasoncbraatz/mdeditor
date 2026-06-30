/* hoedown_harness.c — ASan/UBSan fuzz harness for hoedown 3.0.7
 * Mirrors MacDown's render config (all extensions; nesting = SIZE_MAX, matching
 * the raw/unguarded parser). Finding-7a fix is LANDED (2026-06-30): the product
 * caps kMPRendererNestingLevel=1000 in MPRenderer.m. run.sh drives this harness at
 * MDFUZZ_NESTING=1000 to model that product config (deep_blockquote is clean there);
 * the default below stays SIZE_MAX so the raw-parser hazard is still reproducible.
 * Reads a markdown file and renders
 * it to HTML, exactly the attacker-reachable path for a malicious .md body.
 *
 * Env overrides (for controlled tests):
 *   MDFUZZ_NESTING=<n>   override nesting cap (default SIZE_MAX = current HEAD;
 *                        set 1000 to model the recommended finding-7a fix)
 *   MDFUZZ_SMARTY=1      also run hoedown_html_smartypants (MacDown does when on)
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "document.h"
#include "html.h"
#include "buffer.h"

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s <file.md>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0) n = 0;
    uint8_t *buf = (uint8_t *)malloc((size_t)n + 1);
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);

    int ext = HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_FOOTNOTES |
              HOEDOWN_EXT_AUTOLINK | HOEDOWN_EXT_STRIKETHROUGH | HOEDOWN_EXT_UNDERLINE |
              HOEDOWN_EXT_HIGHLIGHT | HOEDOWN_EXT_QUOTE | HOEDOWN_EXT_SUPERSCRIPT |
              HOEDOWN_EXT_MATH | HOEDOWN_EXT_NO_INTRA_EMPHASIS | HOEDOWN_EXT_SPACE_HEADERS |
              HOEDOWN_EXT_MATH_EXPLICIT;

    size_t nesting = SIZE_MAX;  /* raw/unguarded default; product caps at 1000 (finding 7a LANDED). Override via MDFUZZ_NESTING. */
    const char *nv = getenv("MDFUZZ_NESTING");
    if (nv && *nv) nesting = (size_t)strtoull(nv, NULL, 10);

    hoedown_renderer *r = hoedown_html_renderer_new(0, 0);
    hoedown_document *doc = hoedown_document_new(r, (hoedown_extensions)ext, nesting);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    hoedown_document_render(doc, ob, buf, got);

    const char *sv = getenv("MDFUZZ_SMARTY");
    if (sv && atoi(sv)) {
        hoedown_buffer *sb = hoedown_buffer_new(64);
        hoedown_html_smartypants(sb, ob->data, ob->size);
        hoedown_buffer_free(sb);
    }

    fwrite(ob->data, 1, ob->size, stdout);
    hoedown_buffer_free(ob);
    hoedown_document_free(doc);
    hoedown_html_renderer_free(r);
    free(buf);
    return 0;
}
