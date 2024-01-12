# Declare the local Bazel workspace.
# This is *not* included in the published distribution.
workspace(name = "rules_oci")

# Fetch deps needed only locally for development
load(":internal_deps.bzl", "rules_oci_internal_deps")
rules_oci_internal_deps()

load("@io_bazel_stardoc//:setup.bzl", "stardoc_repositories")
stardoc_repositories()

# Fetch our "runtime" dependencies which users need as well
load("//oci:dependencies.bzl", "rules_oci_dependencies")
rules_oci_dependencies()

load("//oci:repositories.bzl", "LATEST_CRANE_VERSION", "LATEST_ZOT_VERSION", "oci_register_toolchains")
oci_register_toolchains(
    name = "oci",
    crane_version = LATEST_CRANE_VERSION,
    zot_version = LATEST_ZOT_VERSION,
)

load("//cosign:repositories.bzl", "cosign_register_toolchains")
cosign_register_toolchains(name = "oci_cosign")

# For running our own unit tests
load("@bazel_skylib//lib:unittest.bzl", "register_unittest_toolchains")
register_unittest_toolchains()

load("@container_structure_test//:repositories.bzl", "container_structure_test_register_toolchain")
container_structure_test_register_toolchain(name = "container_structure_test")

load("@aspect_bazel_lib//lib:repositories.bzl", "aspect_bazel_lib_dependencies", "aspect_bazel_lib_register_toolchains")
aspect_bazel_lib_dependencies()
aspect_bazel_lib_register_toolchains()

# Gazelle, for generating bzl_library targets
load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")

go_rules_dependencies()

go_register_toolchains(version = "1.17.2")

load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")
gazelle_dependencies()

# Rules pkg
load("@rules_pkg//:deps.bzl", "rules_pkg_dependencies")
rules_pkg_dependencies()


# For sign_external test
new_local_repository(
    name = "empty_image",
    build_file = "//examples/sign_external:BUILD.template",
    path = "examples/sign_external/workspace",
)

# For attest_external test
new_local_repository(
    name = "example_sbom",
    build_file = "//examples/attest_external:BUILD.template",
    path = "examples/attest_external/workspace",
)

load(":fetch.bzl", "fetch_images")

fetch_images()
