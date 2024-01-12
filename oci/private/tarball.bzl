"""Create a tarball from oci_image that can be loaded by runtimes such as podman and docker.

For example, given an `:image` target, you could write

```
oci_tarball(
    name = "tarball",
    image = ":image",
    repo_tags = ["my-repository:latest"],
)
```

and then run it in a container like so:

```
bazel run :tarball
docker run --rm my-repository:latest
```
"""

load("@aspect_bazel_lib//lib:tar.bzl", "tar_lib")
load("//oci/private:util.bzl", "util")

doc = """Creates tarball from OCI layouts that can be loaded into docker daemon without needing to publish the image first.

Passing anything other than oci_image to the image attribute will lead to build time errors.
"""

attrs = {
    "format": attr.string(
        default = "docker",
        doc = "Format of image to generate. Options are: docker, oci. Currently, when the input image is an image_index, only oci is supported, and when the input image is an image, only docker is supported. Conversions between formats may be supported in the future.",
        values = ["docker", "oci"],
    ),
    "image": attr.label(mandatory = True, allow_single_file = True, doc = "Label of a directory containing an OCI layout, typically `oci_image`"),
    "repo_tags": attr.label(
        doc = """\
            a file containing repo_tags, one per line.
            """,
        allow_single_file = [".txt"],
        mandatory = True,
    ),
    "loader": attr.label(
        doc = """\
            Alternative target for a container cli tool that will be
            used to load the image into the local engine when using `bazel run` on this oci_tarball.

            By default, we look for `docker` or `podman` on the PATH, and run the `load` command.
            
            > Note that rules_docker has an "incremental loader" which has better performance, see
            > Follow https://github.com/bazel-contrib/rules_oci/issues/454 for similar behavior in rules_oci.

            See the _run_template attribute for the script that calls this loader tool.
            """,
        allow_single_file = True,
        mandatory = False,
        executable = True,
        cfg = "target",
    ),
    "_tarball_sh": attr.label(allow_single_file = True, default = "//oci/private:tarball.sh.tpl"),
    "_windows_constraint": attr.label(default = "@platforms//os:windows"),
}


def _mtree_line(dest, type, content = None, uid = "0", gid = "0", time = "0.0", mode = "0755"):
    # mtree expects paths to start with ./ so normalize paths that starts with
    # `/` or relative path (without / and ./)
    if not dest.startswith("."):
        if not dest.startswith("/"):
            dest = "/" + dest
        dest = "." + dest
    spec = [
        dest,
        "uid=" + uid,
        "gid=" + gid,
        "time=" + time,
        "mode=" + mode,
        "type=" + type,
    ]
    if content:
        spec.append("content=" + content)
    return " ".join(spec)

def _expand(file, expander):
    expanded = expander.expand(file)
    lines = []
    for e in expanded:
        path = e.tree_relative_path
        segments = path.split("/")
        for i in range(1, len(segments)):
            parent = "/".join(segments[:i])
            lines.append(_mtree_line(parent, "dir"))
        if path.startswith("blobs/"):
            path += ".tar.gz"
        lines.append(_mtree_line(path, "file", content = e.short_path))
    return lines

def _create_executable(ctx, type, output, mtree, jq, bsdtar, transform):
    executable = ctx.actions.declare_file("%s_%s.sh" % (ctx.attr.name, type))
    ctx.actions.expand_template(
        template = ctx.file._tarball_sh,
        output = executable,
        is_executable = True,
        substitutions = {
            "{{bsdtar}}": transform(bsdtar),
            "{{jq}}": transform(jq),
            "{{image}}": transform(ctx.file.image),
            "{{mtree}}": transform(mtree),
            "{{tags}}": transform(ctx.file.repo_tags),
            "{{output}}": output
        },
    )
    return executable

def _tarball_impl(ctx):
    bsdtar = ctx.toolchains[tar_lib.toolchain_type].tarinfo.binary
    jq = ctx.toolchains["@aspect_bazel_lib//lib:jq_toolchain_type"].jqinfo.bin

    # Mtree
    mtree = ctx.actions.declare_file(ctx.attr.name + ".spec")
    content = ctx.actions.args()
    content.set_param_file_format("multiline")
    content.add("#mtree")
    content.add_all(
        ctx.files.image,
        map_each = _expand,
        expand_directories = True,
        uniquify = True,
    )
    ctx.actions.write(mtree, content = content)

    create_executable_kwargs = dict(bsdtar = bsdtar, jq = jq, mtree = mtree)

    # Expensive tarball action.
    executable = _create_executable(ctx, type = "action", transform = lambda x: x.path, **create_executable_kwargs)
    tarball = ctx.actions.declare_file("{}/tarball.tar".format(ctx.label.name))
    ctx.actions.run(
        executable = util.maybe_wrap_launcher_for_windows(ctx, executable),
        inputs = [ctx.file.image, ctx.file.repo_tags, executable],
        outputs = [tarball],
        tools = [jq],
        mnemonic = "OCITarball",
        progress_message = "OCI Tarball %{label}"
    )

    executable = _create_executable(ctx, type = "run", transform = lambda x: x.short_path, **create_executable_kwargs)
    runfiles = ctx.runfiles(files = [jq, bsdtar, mtree, ctx.file.image, ctx.file.repo_tags] + ctx.files.loader)

    return [
        DefaultInfo(files = depset([]), runfiles = runfiles, executable = executable),
        OutputGroupInfo(tarball = depset([tarball]))
    ]

oci_tarball = rule(
    implementation = _tarball_impl,
    attrs = attrs,
    doc = doc,
    toolchains = [
        tar_lib.toolchain_type,
        "@bazel_tools//tools/sh:toolchain_type",
        "@aspect_bazel_lib//lib:jq_toolchain_type",
    ],
    executable = True,
)
