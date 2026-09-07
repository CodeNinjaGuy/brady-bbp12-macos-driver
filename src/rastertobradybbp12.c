/*
 * rastertobradybbp12 - CUPS raster filter for the Brady BBP12 thermal printer.
 *
 * Converts CUPS raster input into TSPL (TSC Printer Language), which is what
 * the BBP12 speaks natively at 300 dpi.
 *
 * Part of the Brady BBP12 macOS driver
 *   https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
 *
 * Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
 * Released under the MIT License. See LICENSE for details.
 *
 * Independent driver. Not affiliated with, endorsed by, or derived from
 * Brady Corporation or any commercial third-party driver.
 *
 * Usage (CUPS calls this): rastertobradybbp12 job user title copies options [file]
 */

#include <cups/cups.h>
#include <cups/ppd.h>
#include <cups/raster.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <ctype.h>

static volatile sig_atomic_t Canceled = 0;

static void
cancel_job(int sig)
{
  (void)sig;
  Canceled = 1;
}

#define BBP12_CONF "/Library/Printers/Brady/bbp12.conf"

/*
 * Load printer calibration from BBP12_CONF.  Lines are "Key Value", "#" starts
 * a comment.  These entries deliberately override the job ticket: the print
 * origin is a property of the hardware, not of a single job.
 */
static int
load_config(const char *path, int num_opts, cups_option_t **opts)
{
  FILE *fp;
  char  line[512];

  if ((fp = fopen(path, "r")) == NULL)
    return num_opts;

  while (fgets(line, sizeof(line), fp))
  {
    char *p = line, *key, *val, *end;

    while (isspace((unsigned char)*p))
      p ++;

    if (*p == '#' || *p == '\0')
      continue;

    key = p;
    while (*p && !isspace((unsigned char)*p) && *p != '=' && *p != ':')
      p ++;

    if (!*p)
      continue;

    *p++ = '\0';

    while (*p && (isspace((unsigned char)*p) || *p == '=' || *p == ':'))
      p ++;

    val = p;
    end = val + strlen(val);
    while (end > val && isspace((unsigned char)end[-1]))
      end --;
    *end = '\0';

    if (*val)
    {
      num_opts = cupsAddOption(key, val, num_opts, opts);
      fprintf(stderr, "DEBUG: Brady BBP12: config %s=%s\n", key, val);
    }
  }

  fclose(fp);

  return num_opts;
}

/*
 * Look up an option: job options win, PPD defaults are the fallback.
 */
static const char *
opt_value(ppd_file_t *ppd, int num_opts, cups_option_t *opts,
          const char *name, const char *dflt)
{
  const char *val = cupsGetOption(name, num_opts, opts);

  if (!val && ppd)
  {
    ppd_choice_t *choice = ppdFindMarkedChoice(ppd, name);

    if (choice && choice->choice[0])
      val = choice->choice;
  }

  if (!val || !*val)
    return dflt;

  /* CUPS reports custom option values as "Custom.<value>". */
  if (!strncasecmp(val, "Custom.", 7))
    val += 7;

  return *val ? val : dflt;
}

/*
 * Decode one raster page into an 8-bit grayscale buffer (0 = black, 255 = white).
 * Returns NULL on error.
 */
static unsigned char *
page_to_gray(cups_raster_t *ras, cups_page_header2_t *h)
{
  unsigned       width  = h->cupsWidth;
  unsigned       height = h->cupsHeight;
  unsigned       bpp    = h->cupsBitsPerPixel;
  unsigned       cs     = h->cupsColorSpace;
  unsigned char *line, *gray, *g;
  unsigned       x, y;
  int            inverted;   /* 1 => sample value counts up towards black */

  if (!width || !height)
  {
    fprintf(stderr, "ERROR: Brady BBP12: empty page (%ux%u).\n", width, height);
    return NULL;
  }

  /* K/SK/CMYK style spaces count upwards to black, W/SW/RGB count to white. */
  inverted = (cs == CUPS_CSPACE_K || cs == CUPS_CSPACE_SILVER ||
              cs == CUPS_CSPACE_GOLD || cs == CUPS_CSPACE_WHITE);

  if ((line = malloc(h->cupsBytesPerLine)) == NULL)
    return NULL;

  if ((gray = malloc((size_t)width * height)) == NULL)
  {
    free(line);
    return NULL;
  }

  for (y = 0; y < height; y ++)
  {
    g = gray + (size_t)y * width;

    if (cupsRasterReadPixels(ras, line, h->cupsBytesPerLine) == 0)
    {
      /* Short page - pad the remainder with white so we still print something. */
      memset(g, 255, (size_t)(height - y) * width);
      break;
    }

    switch (bpp)
    {
      case 1 :
          for (x = 0; x < width; x ++)
          {
            unsigned bit = (line[x / 8] >> (7 - (x & 7))) & 1;
            g[x] = inverted ? (bit ? 0 : 255) : (bit ? 255 : 0);
          }
          break;

      case 8 :
          for (x = 0; x < width; x ++)
            g[x] = inverted ? (unsigned char)(255 - line[x]) : line[x];
          break;

      case 16 :   /* 8-bit gray + alpha, or 16-bit gray: take the high byte */
          for (x = 0; x < width; x ++)
            g[x] = inverted ? (unsigned char)(255 - line[x * 2]) : line[x * 2];
          break;

      case 24 :   /* RGB */
          for (x = 0; x < width; x ++)
          {
            const unsigned char *p = line + x * 3;
            g[x] = (unsigned char)((p[0] * 54 + p[1] * 183 + p[2] * 19) >> 8);
          }
          break;

      case 32 :   /* CMYK */
          for (x = 0; x < width; x ++)
          {
            const unsigned char *p = line + x * 4;
            int r = (255 - p[0]) * (255 - p[3]) / 255;
            int gr = (255 - p[1]) * (255 - p[3]) / 255;
            int b = (255 - p[2]) * (255 - p[3]) / 255;
            g[x] = (unsigned char)((r * 54 + gr * 183 + b * 19) >> 8);
          }
          break;

      default :
          fprintf(stderr, "ERROR: Brady BBP12: unsupported raster format "
                          "(%u bits/pixel, colorspace %u).\n", bpp, cs);
          free(line);
          free(gray);
          return NULL;
    }
  }

  free(line);
  return gray;
}

/*
 * Pack the grayscale page into a TSPL bitmap: one bit per dot, 1 = white,
 * 0 = black (that is what the BITMAP command expects).
 */
static unsigned char *
gray_to_tspl_bits(unsigned char *gray, unsigned width, unsigned height,
                  size_t row_bytes, int threshold, int diffuse)
{
  unsigned char *bits;
  unsigned       x, y;
  int           *err_cur = NULL, *err_next = NULL;

  if ((bits = malloc(row_bytes * height)) == NULL)
    return NULL;

  memset(bits, 0xff, row_bytes * height);     /* all white */

  if (diffuse)
  {
    err_cur  = calloc(width + 2, sizeof(int));
    err_next = calloc(width + 2, sizeof(int));

    if (!err_cur || !err_next)
    {
      free(err_cur);
      free(err_next);
      free(bits);
      return NULL;
    }
  }

  for (y = 0; y < height; y ++)
  {
    unsigned char *src = gray + (size_t)y * width;
    unsigned char *dst = bits + (size_t)y * row_bytes;

    for (x = 0; x < width; x ++)
    {
      int value = src[x];
      int black;

      if (diffuse)
        value += err_cur[x + 1] / 16;

      if (value < 0)
        value = 0;
      else if (value > 255)
        value = 255;

      black = (value < threshold);

      if (black)
        dst[x / 8] &= (unsigned char)~(1 << (7 - (x & 7)));

      if (diffuse)
      {
        int quant_err = value - (black ? 0 : 255);

        err_cur[x + 2]  += quant_err * 7;
        err_next[x]     += quant_err * 3;
        err_next[x + 1] += quant_err * 5;
        err_next[x + 2] += quant_err * 1;
      }
    }

    if (diffuse)
    {
      int *swap = err_cur;
      err_cur   = err_next;
      err_next  = swap;
      memset(err_next, 0, (width + 2) * sizeof(int));
    }
  }

  free(err_cur);
  free(err_next);

  return bits;
}

int
main(int argc, char *argv[])
{
  int                 fd = 0;
  cups_raster_t      *ras;
  cups_page_header2_t header;
  ppd_file_t         *ppd = NULL;
  int                 num_opts;
  cups_option_t      *opts = NULL;
  const char         *ppd_path;
  int                 page = 0;
  int                 copies;
  const char         *density, *speed, *direction, *media, *gap, *gap_offset;
  const char         *ribbon, *mirror, *threshold_s, *dither, *xoff_s, *yoff_s;
  int                 threshold, diffuse, xoff, yoff;
  double              xoff_mm, yoff_mm;
#if defined(HAVE_SIGACTION) || defined(__APPLE__)
  struct sigaction    action;
#endif

  if (argc < 6 || argc > 7)
  {
    fputs("Usage: rastertobradybbp12 job user title copies options [file]\n", stderr);
    return 1;
  }

  if (argc == 7)
  {
    if ((fd = open(argv[6], O_RDONLY)) < 0)
    {
      fprintf(stderr, "ERROR: Brady BBP12: unable to open raster file \"%s\": %s\n",
              argv[6], strerror(errno));
      return 1;
    }
  }

  copies = atoi(argv[4]);
  if (copies < 1)
    copies = 1;

  num_opts = cupsParseOptions(argv[5], 0, &opts);
  num_opts = load_config(BBP12_CONF, num_opts, &opts);

  if ((ppd_path = getenv("PPD")) != NULL && (ppd = ppdOpenFile(ppd_path)) != NULL)
  {
    ppdMarkDefaults(ppd);
    cupsMarkOptions(ppd, num_opts, opts);
  }

  density     = opt_value(ppd, num_opts, opts, "BradyDensity",   "8");
  speed       = opt_value(ppd, num_opts, opts, "BradySpeed",     "2");
  direction   = opt_value(ppd, num_opts, opts, "BradyDirection", "1");
  mirror      = opt_value(ppd, num_opts, opts, "BradyMirror",    "0");
  media       = opt_value(ppd, num_opts, opts, "BradyMediaType", "Gap");
  gap         = opt_value(ppd, num_opts, opts, "BradyGap",       "3");
  gap_offset  = opt_value(ppd, num_opts, opts, "BradySensorOffset", "0");
  ribbon      = opt_value(ppd, num_opts, opts, "BradyRibbon",    "On");
  threshold_s = opt_value(ppd, num_opts, opts, "BradyThreshold", "128");
  dither      = opt_value(ppd, num_opts, opts, "BradyDither",    "Threshold");
  xoff_s      = opt_value(ppd, num_opts, opts, "BradyXOffset",   "0");
  yoff_s      = opt_value(ppd, num_opts, opts, "BradyYOffset",   "0");

  threshold = atoi(threshold_s);
  if (threshold < 1)
    threshold = 1;
  else if (threshold > 254)
    threshold = 254;

  diffuse = (strcasecmp(dither, "Diffusion") == 0);
  xoff    = atoi(xoff_s);
  yoff    = atoi(yoff_s);

  fprintf(stderr, "INFO: Brady BBP12: offset %d,%d dots; density %s; speed %s; "
                  "media %s; gap %s mm\n", xoff, yoff, density, speed, media, gap);

#if defined(HAVE_SIGACTION) || defined(__APPLE__)
  memset(&action, 0, sizeof(action));
  sigemptyset(&action.sa_mask);
  action.sa_handler = cancel_job;
  sigaction(SIGTERM, &action, NULL);
#else
  signal(SIGTERM, cancel_job);
#endif

  if ((ras = cupsRasterOpen(fd, CUPS_RASTER_READ)) == NULL)
  {
    fputs("ERROR: Brady BBP12: unable to read raster data.\n", stderr);
    if (ppd)
      ppdClose(ppd);
    return 1;
  }

  while (!Canceled && cupsRasterReadHeader2(ras, &header))
  {
    unsigned char *gray, *bits;
    size_t         row_bytes;
    double         width_mm, height_mm;

    page ++;
    fprintf(stderr, "PAGE: %d %d\n", page, copies);
    fprintf(stderr, "INFO: Brady BBP12: rendering page %d (%ux%u dots, %ux%u dpi)\n",
            page, header.cupsWidth, header.cupsHeight,
            header.HWResolution[0], header.HWResolution[1]);

    if ((gray = page_to_gray(ras, &header)) == NULL)
      break;

    row_bytes = (header.cupsWidth + 7) / 8;

    bits = gray_to_tspl_bits(gray, header.cupsWidth, header.cupsHeight,
                             row_bytes, threshold, diffuse);
    free(gray);

    if (!bits)
    {
      fputs("ERROR: Brady BBP12: out of memory while packing the bitmap.\n", stderr);
      break;
    }

    /* Prefer the PPD page dimensions; fall back to dots / resolution. */
    if (header.PageSize[0] > 0.0 && header.PageSize[1] > 0.0)
    {
      width_mm  = header.PageSize[0] * 25.4 / 72.0;
      height_mm = header.PageSize[1] * 25.4 / 72.0;
    }
    else
    {
      width_mm  = header.cupsWidth  * 25.4 / (header.HWResolution[0] ? header.HWResolution[0] : 203);
      height_mm = header.cupsHeight * 25.4 / (header.HWResolution[1] ? header.HWResolution[1] : 203);
    }

    /*
     * The print origin is the left edge of the print head, which is not
     * necessarily the left edge of the media.  Grow the SIZE window by the
     * offsets so that shifting the bitmap does not push it past the clip
     * boundary and lose the trailing edge.
     */
    xoff_mm = xoff * 25.4 / (header.HWResolution[0] ? header.HWResolution[0] : 300);
    yoff_mm = yoff * 25.4 / (header.HWResolution[1] ? header.HWResolution[1] : 300);

    printf("SIZE %.2f mm,%.2f mm\r\n", width_mm + xoff_mm, height_mm + yoff_mm);

    if (strcasecmp(media, "Continuous") == 0)
      printf("GAP 0 mm,0 mm\r\n");
    else if (strcasecmp(media, "BlackMark") == 0)
      printf("BLINE %s mm,%s mm\r\n", gap, gap_offset);
    else
      printf("GAP %s mm,%s mm\r\n", gap, gap_offset);

    printf("DIRECTION %s,%s\r\n", direction, mirror);
    printf("REFERENCE 0,0\r\n");
    printf("SET RIBBON %s\r\n", (strcasecmp(ribbon, "Off") == 0) ? "OFF" : "ON");
    printf("DENSITY %s\r\n", density);
    printf("SPEED %s\r\n", speed);
    printf("CLS\r\n");

    printf("BITMAP %d,%d,%u,%u,0,", xoff, yoff,
           (unsigned)row_bytes, header.cupsHeight);
    fwrite(bits, 1, row_bytes * header.cupsHeight, stdout);
    printf("\r\n");

    printf("PRINT 1,%d\r\n", copies);
    fflush(stdout);

    free(bits);
  }

  cupsRasterClose(ras);

  if (fd != 0)
    close(fd);

  if (ppd)
    ppdClose(ppd);

  cupsFreeOptions(num_opts, opts);

  if (page == 0)
  {
    fputs("ERROR: Brady BBP12: no pages were found in the raster stream.\n", stderr);
    return 1;
  }

  fprintf(stderr, "INFO: Brady BBP12: %d page(s) sent.\n", page);

  return 0;
}
