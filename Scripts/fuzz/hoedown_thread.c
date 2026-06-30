/* hoedown_thread.c — render on a pthread with a 512KB stack (matching
 * NSOperationQueue, where MacDown's parseMarkdown: runs). Used to find the
 * real production-safe max_nesting threshold at -O0. argv[1]=file argv[2]=nesting
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include "document.h"
#include "html.h"
#include "buffer.h"

static uint8_t *g_buf; static size_t g_got; static size_t g_nest;

static void *worker(void *arg) {
    (void)arg;
    int ext = HOEDOWN_EXT_TABLES|HOEDOWN_EXT_FENCED_CODE|HOEDOWN_EXT_FOOTNOTES|
              HOEDOWN_EXT_AUTOLINK|HOEDOWN_EXT_STRIKETHROUGH|HOEDOWN_EXT_UNDERLINE|
              HOEDOWN_EXT_HIGHLIGHT|HOEDOWN_EXT_QUOTE|HOEDOWN_EXT_SUPERSCRIPT|
              HOEDOWN_EXT_MATH|HOEDOWN_EXT_NO_INTRA_EMPHASIS|HOEDOWN_EXT_SPACE_HEADERS|
              HOEDOWN_EXT_MATH_EXPLICIT;
    hoedown_renderer *r = hoedown_html_renderer_new(0,0);
    hoedown_document *doc = hoedown_document_new(r,(hoedown_extensions)ext,g_nest);
    hoedown_buffer *ob = hoedown_buffer_new(64);
    hoedown_document_render(doc, ob, g_buf, g_got);
    hoedown_buffer_free(ob); hoedown_document_free(doc); hoedown_html_renderer_free(r);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr,"usage: %s file nesting\n",argv[0]); return 2; }
    FILE *f = fopen(argv[1],"rb"); if(!f){perror("fopen");return 2;}
    fseek(f,0,SEEK_END); long n=ftell(f); fseek(f,0,SEEK_SET); if(n<0)n=0;
    g_buf=malloc((size_t)n+1); g_got=fread(g_buf,1,(size_t)n,f); fclose(f);
    g_nest=(size_t)strtoull(argv[2],NULL,10);

    pthread_attr_t attr; pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 512*1024);  /* NSOperationQueue default */
    pthread_t t;
    if (pthread_create(&t,&attr,worker,NULL)!=0){fprintf(stderr,"thread fail\n");return 3;}
    pthread_join(t,NULL);
    pthread_attr_destroy(&attr);
    free(g_buf);
    return 0;
}
