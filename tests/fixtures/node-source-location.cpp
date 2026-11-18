#include <source_location>

#include <cstdio>
#include <cstring>

static_assert(sizeof(std::source_location) == sizeof(void*),
              "the i686 V8 source_location member must retain pointer-sized layout");

static std::source_location caller_location(
    std::source_location location = std::source_location::current()) noexcept {
  return location;
}

int main() {
  const unsigned expected_line = __LINE__ + 1;
  const std::source_location location = caller_location();
  if (location.line() != expected_line ||
      std::strstr(location.file_name(), "node-source-location.cpp") == nullptr ||
      std::strstr(location.function_name(), "main") == nullptr) {
    std::fprintf(stderr, "source_location call-site capture mismatch: %s:%u (%s)\n",
                 location.file_name(), location.line(), location.function_name());
    return 1;
  }
  std::printf("source_location=PASS\nsource_location_size=%zu\npointer_size=%zu\ncaller_line=%u\n",
              sizeof(location), sizeof(void*), location.line());
  return 0;
}
