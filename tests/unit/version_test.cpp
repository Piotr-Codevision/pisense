#include "pisense/version.hpp"

#include <gtest/gtest.h>
#include <regex>
#include <string>

TEST(VersionTest, HasMajorMinorPatchFormat)
{
    const std::string version{pisense::version()};
    EXPECT_TRUE(std::regex_match(version, std::regex{R"(\d+\.\d+\.\d+)"})) << version;
}
