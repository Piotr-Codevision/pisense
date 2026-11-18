#ifndef PISENSE_VERSION_HPP
#define PISENSE_VERSION_HPP

#include <string_view>

namespace pisense {

// Returns the PiSense version string ("<major>.<minor>.<patch>").
[[nodiscard]] std::string_view version() noexcept;

} // namespace pisense

#endif // PISENSE_VERSION_HPP
