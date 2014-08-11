#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <libfreenect/libfreenect.h>
#include <cv.h>
#include <opencv2/imgproc/imgproc.hpp>

using namespace cv;

static const int width = 640;
static const int height = 480;

freenect_context *f_ctx;
freenect_device *f_dev;
int fifo_fd;
bool dummy;
bool shouldBlur;

void postprocess(uint16_t *depth)
{
  static Mat *fullsize = NULL;
  static Mat *resized = NULL;
  if (fullsize == NULL)
    fullsize = new Mat(height, width, CV_16UC1, depth);
  if (resized == NULL)
    resized = new Mat(320, 240, CV_16UC1);

  resize(*fullsize, *resized, Size(320, 240));

  if (shouldBlur) {
    blur(*resized, *resized, Size(9, 9));
    blur(*resized, *resized, Size(9, 9));
    blur(*resized, *resized, Size(9, 9));
  }

  write(fifo_fd, resized->data, 320 * 240 * sizeof(uint16_t));
}

void kinect_depth_callback(freenect_device *dev, void *v_depth, uint32_t timestamp)
{
  postprocess((uint16_t *)v_depth);
}

int kinect_init(void)
{
  if (freenect_init(&f_ctx, NULL) < 0) {
    printf("freenect_init() failed\n");
    return -1;
  }

  freenect_set_log_level(f_ctx, FREENECT_LOG_INFO);
  freenect_select_subdevices(f_ctx, (freenect_device_flags)(FREENECT_DEVICE_MOTOR | FREENECT_DEVICE_CAMERA));

  if (freenect_num_devices(f_ctx) < 1) {
    printf("No devices found\n");
    freenect_shutdown(f_ctx);
    return -1;
  }

  if (freenect_open_device(f_ctx, &f_dev, 0) < 0) {
    printf("Could not open device\n");
    freenect_shutdown(f_ctx);
    return -1;
  }

  freenect_set_led(f_dev, LED_OFF);

  freenect_set_depth_callback(f_dev, kinect_depth_callback);
  freenect_set_depth_mode(f_dev, freenect_find_depth_mode(FREENECT_RESOLUTION_MEDIUM, FREENECT_DEPTH_MM));

  freenect_start_depth(f_dev);
  freenect_set_flag(f_dev, FREENECT_MIRROR_DEPTH, FREENECT_ON);

  return 0;
}

void kinect_destroy(void)
{
  freenect_stop_depth(f_dev);

  freenect_close_device(f_dev);
  freenect_shutdown(f_ctx);
}

int kinect_loop(void)
{
  return freenect_process_events(f_ctx);
}

int dummy_init(void)
{
  return 1;
}

void dummy_destroy(void)
{
}

int dummy_loop(void)
{
  static uint16_t *buffer = NULL;
  static uint16_t value = 0;

  if (buffer == NULL)
    buffer = (uint16_t *)malloc(width * height * sizeof(uint16_t));

  for (int i = 0; i < width * height; i++)
    buffer[i] = (i / width / 20) / 24.0 * value;

  postprocess(buffer);

  value += 5;

  if (value >= 1 << 11)
    value = 0;

  usleep(30000);

  return 1;
}

int main(int argc, char **argv)
{
  dummy = false;
  shouldBlur = false;
  char *fifo_fn = NULL;

  int c;
  while ((c = getopt(argc, argv, "bdf:")) != -1) {
    switch (c) {
      case 'b':
        shouldBlur = true;
        break;
      case 'd':
        dummy = true;
        break;
      case 'f':
        fifo_fn = optarg;
        break;
    }
  }

  if (fifo_fn == NULL) {
    printf("%s - dump Kinect depth data to a fifo\n", argv[0]);
    printf("\n");
    printf("Usage: %s [-b] [-d] -f fifo_file\n", argv[0]);
    return EXIT_FAILURE;
  }

  if (access(fifo_fn, F_OK) < 0) {
    if (mkfifo(fifo_fn, 0660) < 0) {
      printf("mkfifo() failed: %s\n", strerror(errno));
      return EXIT_FAILURE;
    }
  }

  if ((fifo_fd = open(fifo_fn, O_WRONLY)) < 0) {
    printf("open() fifo failed: %s\n", strerror(errno));
    return EXIT_FAILURE;
  }

  if (dummy) {
    if (dummy_init() < 0)
      return EXIT_FAILURE;

    while (dummy_loop() >= 0)
      ;

    dummy_destroy();
  } else {
    if (kinect_init() < 0)
      return EXIT_FAILURE;

    while (kinect_loop() >= 0)
      ;

    kinect_destroy();
  }

  return 0;
}
