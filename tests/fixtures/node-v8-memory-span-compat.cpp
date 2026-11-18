#include <array>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <span>
#include <utility>
#include <vector>

namespace v8_crdtp {
template <typename T>
using span = std::span<const T>;
}  // namespace v8_crdtp

namespace v8 {
template <typename T>
struct MemorySpan {
  T* data;
  std::size_t size;
};
}  // namespace v8

class Binary {
 public:
  static Binary fromSpan(v8_crdtp::span<uint8_t> span) {
    return Binary(
        std::make_shared<std::vector<uint8_t>>(span.begin(), span.end()));
  }
  static Binary fromSpan(v8::MemorySpan<const uint8_t> span) {
    return Binary(
        std::make_shared<std::vector<uint8_t>>(span.data,
                                                span.data + span.size));
  }

  const std::vector<uint8_t>& bytes() const { return *bytes_; }

 private:
  explicit Binary(std::shared_ptr<std::vector<uint8_t>> bytes)
      : bytes_(std::move(bytes)) {}

  std::shared_ptr<std::vector<uint8_t>> bytes_;
};

int main() {
  std::array<uint8_t, 4> input{0, 17, 128, 255};
  Binary copied = Binary::fromSpan(
      v8_crdtp::span<uint8_t>(input.data(), input.size()));
  input[0] = 42;
  if (copied.bytes() != std::vector<uint8_t>({0, 17, 128, 255})) return 1;
  std::puts("memory_span_nonempty_copy=PASS");

  Binary empty = Binary::fromSpan(v8_crdtp::span<uint8_t>());
  if (!empty.bytes().empty()) return 1;
  std::puts("memory_span_empty_copy=PASS");
}
