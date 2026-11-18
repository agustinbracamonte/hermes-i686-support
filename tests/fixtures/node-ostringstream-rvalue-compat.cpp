#include <sstream>
#include <string>

std::string source_location_string() {
#if defined(HERMES_FORCE_NODE_I686_OSSTREAM_COMPAT) || \
    (defined(__i386__) && defined(__clang__))
  std::ostringstream stream;
  stream << "function" << '@' << "file.cc" << ':' << 27;
  return stream.str();
#else
  return (std::ostringstream{} << "function" << '@' << "file.cc" << ':'
                               << 27)
      .str();
#endif
}

int main() {
  return source_location_string() == "function@file.cc:27" ? 0 : 1;
}
