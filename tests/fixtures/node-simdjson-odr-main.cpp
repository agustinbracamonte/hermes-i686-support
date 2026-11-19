#include <string>
#include <iostream>

std::string odr_from_a();
std::string odr_from_b();

int main() {
  if (odr_from_a() != "42" || odr_from_b() != "65 ('A')") return 1;
  std::cout << "simdjson_header_odr=PASS\n";
}
