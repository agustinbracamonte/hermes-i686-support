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
  MemorySpan() = default;
  template <typename Iterator>
  MemorySpan(Iterator first, std::size_t count)
      : data(std::to_address(first)), size(count) {}
  T* begin() const { return data; }
  T* end() const { return size == 0 ? data : data + size; }
  T* data = nullptr;
  std::size_t size = 0;
};
}  // namespace v8

class Binary {
 public:
#if defined(HERMES_FORCE_NODE_I686_V8_MEMORY_SPAN_COMPAT)
  static Binary fromBytes(const uint8_t* data, std::size_t size) {
    auto bytes = std::make_shared<std::vector<uint8_t>>();
    if (size != 0) bytes->assign(data, data + size);
    return Binary(bytes);
  }
#endif

  static Binary fromSpan(v8_crdtp::span<uint8_t> span) {
#if defined(HERMES_FORCE_NODE_I686_V8_MEMORY_SPAN_COMPAT)
    return fromBytes(span.data(), span.size());
#else
    return Binary(
        std::make_shared<std::vector<uint8_t>>(
            v8::MemorySpan<const uint8_t>(span.begin(), span.size()).begin(),
            v8::MemorySpan<const uint8_t>(span.begin(), span.size()).end()));
#endif
  }
  static Binary fromSpan(v8::MemorySpan<const uint8_t> span) {
    auto bytes = std::make_shared<std::vector<uint8_t>>();
    if (span.size != 0) bytes->assign(span.data, span.data + span.size);
    return Binary(bytes);
  }

  const std::vector<uint8_t>& bytes() const { return *bytes_; }

 private:
  explicit Binary(std::shared_ptr<std::vector<uint8_t>> bytes)
      : bytes_(std::move(bytes)) {}

  std::shared_ptr<std::vector<uint8_t>> bytes_;
};

Binary copy_cached_script(const std::vector<uint8_t>& source) {
#if defined(HERMES_FORCE_NODE_I686_V8_MEMORY_SPAN_COMPAT)
  return Binary::fromBytes(source.data(), source.size());
#else
  return Binary::fromSpan(
      v8::MemorySpan<const uint8_t>(source.begin(), source.size()));
#endif
}

Binary copy_wasm_bytes(v8::MemorySpan<const uint8_t> source) {
#if defined(HERMES_FORCE_NODE_I686_V8_MEMORY_SPAN_COMPAT)
  return Binary::fromBytes(source.data, source.size);
#else
  return Binary::fromSpan(source);
#endif
}

int main() {
  std::array<uint8_t, 4> input{0, 17, 128, 255};
  Binary copied = Binary::fromSpan(
      v8_crdtp::span<uint8_t>(input.data(), input.size()));
  input[0] = 42;
  if (copied.bytes() != std::vector<uint8_t>({0, 17, 128, 255})) return 1;
  std::puts("memory_span_crdtp_nonempty_copy=PASS");

  Binary empty = Binary::fromSpan(v8_crdtp::span<uint8_t>());
  if (!empty.bytes().empty()) return 1;
  std::puts("memory_span_crdtp_empty_copy=PASS");

  std::vector<uint8_t> cached{1, 2, 3, 4};
  Binary cached_copy = copy_cached_script(cached);
  cached[0] = 99;
  if (cached_copy.bytes() != std::vector<uint8_t>({1, 2, 3, 4})) return 1;
  std::puts("memory_span_cached_nonempty_copy=PASS");

  Binary cached_empty = copy_cached_script({});
  if (!cached_empty.bytes().empty()) return 1;
  std::puts("memory_span_cached_empty_copy=PASS");

  std::array<uint8_t, 4> wasm{5, 6, 7, 8};
  Binary wasm_copy = copy_wasm_bytes(
      v8::MemorySpan<const uint8_t>(wasm.data(), wasm.size()));
  wasm[0] = 99;
  if (wasm_copy.bytes() != std::vector<uint8_t>({5, 6, 7, 8})) return 1;
  std::puts("memory_span_wasm_nonempty_copy=PASS");

  Binary wasm_empty = copy_wasm_bytes(v8::MemorySpan<const uint8_t>());
  if (!wasm_empty.bytes().empty()) return 1;
  std::puts("memory_span_wasm_empty_copy=PASS");
}
