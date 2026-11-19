#include "simdjson.h"

std::string odr_from_a() {
  std::string result;
  simdjson::implementation_0::key_selector_detail::append_uint(result, 42);
  return result;
}
