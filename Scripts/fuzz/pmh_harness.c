/* pmh_harness.c — ASan/UBSan fuzz harness for peg-markdown-highlight's
 * generated pmh_parser.c. Mirrors HGMarkdownHighlighter.m: it passes the
 * document's UTF-8 bytes (NUL-terminated) to pmh_markdown_to_elements, then
 * frees the result. This is the attacker-reachable syntax-highlight parse of a
 * malicious .md.
 *
 * Env override: MDFUZZ_PMH_EXT=1 enables pmh_EXT_NOTES (default pmh_EXT_NONE,
 * which is what MacDown ships).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pmh_parser.h"

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s <file.md>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n < 0) n = 0;
    char *text = (char *)malloc((size_t)n + 1);
    size_t got = fread(text, 1, (size_t)n, f);
    text[got] = '\0';   /* pmh uses strlen on the input */
    fclose(f);

    int ext = pmh_EXT_NONE;
    const char *ev = getenv("MDFUZZ_PMH_EXT");
    if (ev && atoi(ev)) ext = pmh_EXT_NOTES;

    pmh_element **result = NULL;
    pmh_markdown_to_elements(text, ext, &result);
    if (result) pmh_free_elements(result);

    free(text);
    return 0;
}
