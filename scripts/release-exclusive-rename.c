#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/stdio.h>
#include <unistd.h>

struct split_path {
  char *storage;
  const char *parent;
  const char *base;
};

static int is_absolute_nonroot_path(const char *path) {
  return path != NULL && path[0] == '/' && path[1] != '\0';
}

static int split_absolute_path(const char *path, struct split_path *result) {
  char *last_slash;

  result->storage = strdup(path);
  if (result->storage == NULL) {
    return -1;
  }
  last_slash = strrchr(result->storage, '/');
  if (last_slash == NULL || last_slash[1] == '\0') {
    free(result->storage);
    result->storage = NULL;
    return -1;
  }
  result->base = last_slash + 1;
  if (strcmp(result->base, ".") == 0 || strcmp(result->base, "..") == 0) {
    free(result->storage);
    result->storage = NULL;
    return -1;
  }
  if (last_slash == result->storage) {
    result->parent = "/";
  } else {
    *last_slash = '\0';
    result->parent = result->storage;
  }
  return 0;
}

int main(int argc, char **argv) {
  struct split_path source_path = {0};
  struct split_path destination_path = {0};
  struct stat source_status;
  struct stat destination_status;
  struct stat post_status;
  int parent_fd = -1;
  int result = 0;

  if (argc != 3 || !is_absolute_nonroot_path(argv[1]) ||
      !is_absolute_nonroot_path(argv[2]) || strcmp(argv[1], argv[2]) == 0) {
    return 64;
  }
  if (split_absolute_path(argv[1], &source_path) != 0 ||
      split_absolute_path(argv[2], &destination_path) != 0 ||
      strcmp(source_path.parent, destination_path.parent) != 0) {
    result = 64;
    goto cleanup;
  }
  parent_fd = open(source_path.parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (parent_fd < 0 ||
      fstatat(parent_fd, source_path.base, &source_status, AT_SYMLINK_NOFOLLOW) != 0 ||
      !S_ISDIR(source_status.st_mode)) {
    result = 65;
    goto cleanup;
  }
  errno = 0;
  if (fstatat(parent_fd, destination_path.base, &destination_status,
              AT_SYMLINK_NOFOLLOW) == 0 ||
      errno != ENOENT) {
    result = 66;
    goto cleanup;
  }
  if (renameatx_np(parent_fd, source_path.base, parent_fd, destination_path.base,
                   RENAME_EXCL) != 0) {
    result = 67;
    goto cleanup;
  }
  if (fstatat(parent_fd, destination_path.base, &post_status,
              AT_SYMLINK_NOFOLLOW) != 0 ||
      !S_ISDIR(post_status.st_mode) || post_status.st_dev != source_status.st_dev ||
      post_status.st_ino != source_status.st_ino) {
    result = 68;
    goto cleanup;
  }
  errno = 0;
  if (fstatat(parent_fd, source_path.base, &destination_status,
              AT_SYMLINK_NOFOLLOW) == 0 ||
      errno != ENOENT) {
    result = 69;
    goto cleanup;
  }

cleanup:
  if (parent_fd >= 0) {
    close(parent_fd);
  }
  free(source_path.storage);
  free(destination_path.storage);
  return result;
}
