/* pmh_thread.c — run pmh_markdown_to_elements on a pthread with a 512KB stack
 * (matching the NSOperationQueue _parseHighlightsQueue where MacDown's syntax
 * highlighting parse actually runs — see HGMarkdownHighlighter.m -requestParsing).
 * Used to (a) find the real production stack-overflow floor for the peg
 * recursive-descent (finding 7b-stack: yy_Label/yy_ExplicitLink/yy_Link/yy_Inline
 * cycle, one cycle per nested '['), and (b) prove the finding-7b-stack input
 * nesting cap in pmh_markdown_to_elements is load-bearing and safely below floor.
 *
 * argv[1] = bracket nesting depth. Generates "[" * depth + "x" + "]" * depth in
 * memory (the deep_brackets.md vector) and parses it on the 512KB stack.
 * Build the guard-OFF control with -DPMH_NO_NESTING_GUARD to measure the raw
 * floor and prove the DoS is real; build guard-ON (default) to prove the cap
 * refuses deep input (rc 0, no parse).
 *
 * Exit: 0 = parsed/refused cleanly; >=128 = crashed (stack-overflow on 512KB).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "pmh_parser.h"

static char *g_text;

static void *worker(void *arg)
{
    (void)arg;
    pmh_element **result = NULL;
    pmh_markdown_to_elements(g_text, pmh_EXT_NONE, &result);
    if (result) pmh_free_elements(result);
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s <bracket-depth>\n", argv[0]); return 2; }
    size_t depth = (size_t)strtoull(argv[1], NULL, 10);

    g_text = (char *)malloc(depth * 2 + 2);
    if (!g_text) { fprintf(stderr, "oom\n"); return 3; }
    size_t i = 0;
    for (size_t k = 0; k < depth; k++) g_text[i++] = '[';
    g_text[i++] = 'x';
    for (size_t k = 0; k < depth; k++) g_text[i++] = ']';
    g_text[i] = '\0';

    pthread_attr_t attr; pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 512 * 1024);   /* NSOperationQueue default */
    pthread_t t;
    if (pthread_create(&t, &attr, worker, NULL) != 0) { fprintf(stderr, "thread fail\n"); return 3; }
    pthread_join(t, NULL);
    pthread_attr_destroy(&attr);
    free(g_text);
    return 0;
}
