local lm = require "luamake"

local SETENV = lm.plat == "msvc" and "set" or "export"
local BGFX_OS
local BGFX_ARGS
local BGFX_BINS

if lm.plat == "msvc" then
    BGFX_OS = "windows"
    BGFX_ARGS = {"--with-windows=10.0", "vs2019"}
    BGFX_BINS = "../bgfx/.build/win64_vs2019/bin/"
elseif lm.plat == "mingw" then
    BGFX_OS = "windows"
    BGFX_ARGS = {"--os=windows", "--gcc=mingw-gcc", "gmake"}
    BGFX_BINS = "../bgfx/.build/win64_mingw-gcc/bin/"
end

GENIE = ("../bx/tools/bin/%s/genie"):format(BGFX_OS)
if lm.plat == "msvc" then
    GENIE = GENIE:gsub("/", "\\")
end

lm:shell "bgfx_init" {
    SETENV, "BGFX_CONFIG=MAX_VIEWS=1024", "&&",
    "cd", "@../bgfx", "&&",
    GENIE, "--with-tools", "--with-shared-lib", "--with-dynamic-runtime", "--with-examples", BGFX_ARGS,
    pool = "console",
}

if lm.plat == "msvc" then
    local msvc = require "msvc"
    local MSBuild = msvc:installpath() / "MSBuild" / "Current" / "Bin" / "MSBuild.exe"
    lm:build "bgfx_build" {
        MSBuild, "/nologo", "@../bgfx/.build/projects/vs2019/bgfx.sln", "/m", "/v:m", "/t:build", ([[/p:Configuration=%s,Platform=x64]]):format(lm.mode),
        pool = "console",
    }
elseif lm.plat == "mingw" then
    local BgfxMakefile = "@../bgfx/.build/projects/gmake-mingw-gcc"
    local BgfxMake = {"make", "--no-print-directory", "-R", "-C", BgfxMakefile, "config="..lm.mode.."64", "-j8" }
    lm:build "bgfx_build" {
        BgfxMake, "bgfx", "bx", "bimg", "bimg_decode", "bgfx-shared-lib", "shaderc", "texturec",
        pool = "console",
    }
end

lm:copy "copy_bgfx_texturec" {
    input = BGFX_BINS .. "texturec"..lm.mode..".exe",
    output = "$bin/texturec.exe",
    deps = "bgfx_build",
}

lm:copy "copy_bgfx_shaderc" {
    input = BGFX_BINS .. "shaderc"..lm.mode..".exe",
    output = "$bin/shaderc.exe",
    deps = "bgfx_build",
}

lm:copy "copy_bgfx_shared_lib" {
    input = BGFX_BINS .. "bgfx-shared-lib"..lm.mode..".dll",
    output = "$bin/bgfx-core.dll",
    deps = "bgfx_build",
}

lm:copy "copy_bgfx_shader" {
    input = "../bgfx/src/bgfx_shader.sh",
    output = "../../packages/resources/shaders/bgfx_shader.sh",
}

lm:copy "copy_bgfx_compute" {
    input = "../bgfx/src/bgfx_compute.sh",
    output = "../../packages/resources/shaders/bgfx_compute.sh",
}

lm:copy "copy_bgfx_examples_common" {
    input = "../bgfx/examples/common/common.sh",
    output = "../../packages/resources/shaders/common.sh",
}

lm:copy "copy_bgfx_examples_shaderlib" {
    input = "../bgfx/examples/common/shaderlib.sh",
    output = "../../packages/resources/shaders/shaderlib.sh",
}

lm:phony "bgfx_make" {
    deps = {
        "copy_bgfx_texturec",
        "copy_bgfx_shaderc",
        "copy_bgfx_shared_lib",
        "copy_bgfx_shader",
        "copy_bgfx_compute",
        "copy_bgfx_examples_common",
        "copy_bgfx_examples_shaderlib",
    }
}
