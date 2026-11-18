#include <bit>
#include <type_traits>

namespace v8::base {
template <class Dest, class Source>
constexpr Dest bit_cast(Source const& source) noexcept {
  static_assert(sizeof(Dest) == sizeof(Source));
  static_assert(std::is_trivially_copyable_v<Source>);
  static_assert(std::is_trivially_copyable_v<Dest>);
#if defined(__i386__) && defined(__clang__) && !defined(__cpp_lib_bit_cast)
  return __builtin_bit_cast(Dest, source);
#else
  return std::bit_cast<Dest, Source>(source);
#endif
}
}  // namespace v8::base

constexpr float kOneAndHalf = v8::base::bit_cast<float>(0x3fc00000U);
static_assert(kOneAndHalf == 1.5f);
static_assert(v8::base::bit_cast<unsigned int>(kOneAndHalf) == 0x3fc00000U);

int main() {
  return v8::base::bit_cast<unsigned int>(1.5f) == 0x3fc00000U ? 0 : 1;
}
