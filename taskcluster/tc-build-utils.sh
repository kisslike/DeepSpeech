#!/bin/bash

set -xe

do_deepspeech_python_build()
{
  cd ${DS_DSDIR}

  package_option=$1

  unset PYTHON_BIN_PATH
  unset PYTHONPATH

  export PATH="${PYENV_ROOT}/bin:$PATH"

  mkdir -p wheels

  SETUP_FLAGS=""
  if [ "${package_option}" = "--cuda" ]; then
    SETUP_FLAGS="--project_name deepspeech-gpu"
  elif [ "${package_option}" = "--tflite" ]; then
    SETUP_FLAGS="--project_name deepspeech-tflite"
  fi

  for pyver_conf in ${SUPPORTED_PYTHON_VERSIONS}; do
    pyver=$(echo "${pyver_conf}" | cut -d':' -f1)
    pyconf=$(echo "${pyver_conf}" | cut -d':' -f2)

    pyalias="${pyver}_${pyconf}"

    maybe_numpy_min_version ${pyver}

    virtualenv_activate "${pyalias}" "deepspeech"

    python --version
    which pip
    which pip3

    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    make -C native_client/python/ \
        TARGET=${SYSTEM_TARGET} \
        RASPBIAN=${SYSTEM_RASPBIAN} \
        TFDIR=${DS_TFDIR} \
        SETUP_FLAGS="${SETUP_FLAGS}" \
        bindings-clean bindings

    cp native_client/python/dist/*.whl wheels

    make -C native_client/python/ bindings-clean

    virtualenv_deactivate "${pyalias}" "deepspeech"
  done;
}

do_deepspeech_decoder_build()
{
  cd ${DS_DSDIR}

  unset PYTHON_BIN_PATH
  unset PYTHONPATH

  export PATH="${PYENV_ROOT}/bin:$PATH"

  mkdir -p wheels

  for pyver_conf in ${SUPPORTED_PYTHON_VERSIONS}; do
    pyver=$(echo "${pyver_conf}" | cut -d':' -f1)
    pyconf=$(echo "${pyver_conf}" | cut -d':' -f2)
    pyalias="${pyver}_${pyconf}"

    maybe_numpy_min_version ${pyver}

    virtualenv_activate "${pyalias}" "deepspeech"

    python --version
    which pip
    which pip3

    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    make -C native_client/ctcdecode/ \
        TARGET=${SYSTEM_TARGET} \
        RASPBIAN=${SYSTEM_RASPBIAN} \
        TFDIR=${DS_TFDIR} \
        NUM_PROCESSES=${DS_CPU_COUNT} \
        bindings

    cp native_client/ctcdecode/dist/*.whl wheels

    make -C native_client/ctcdecode clean-keep-third-party

    virtualenv_deactivate "${pyalias}" "deepspeech"
  done;
}

do_deepspeech_nodejs_build()
{
  rename_to_gpu=$1

  npm update

  # Python 2.7 is required for node-pre-gyp, it is only required to force it on
  # Windows
  if [ "${OS}" = "${TC_MSYS_VERSION}" ]; then
    NPM_ROOT=$(cygpath -u "$(npm root)")
    PYTHON27=":/c/Python27"
    # node-gyp@5.x behaves erratically with VS2015 and MSBuild.exe detection
    npm install node-gyp@4.x node-pre-gyp
  else
    NPM_ROOT="$(npm root)"
    npm install node-gyp@5.x node-pre-gyp
  fi

  export PATH="$NPM_ROOT/.bin/${PYTHON27}:$PATH"

  for node in ${SUPPORTED_NODEJS_VERSIONS}; do
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" make -C native_client/javascript \
      TARGET=${SYSTEM_TARGET} \
      RASPBIAN=${SYSTEM_RASPBIAN} \
      TFDIR=${DS_TFDIR} \
      NODE_ABI_TARGET=--target=$node \
      clean node-wrapper
  done;

  for electron in ${SUPPORTED_ELECTRONJS_VERSIONS}; do
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" make -C native_client/javascript \
      TARGET=${SYSTEM_TARGET} \
      RASPBIAN=${SYSTEM_RASPBIAN} \
      TFDIR=${DS_TFDIR} \
      NODE_ABI_TARGET=--target=$electron \
      NODE_DIST_URL=--disturl=https://electronjs.org/headers \
      NODE_RUNTIME=--runtime=electron \
      clean node-wrapper
  done;

  if [ "${rename_to_gpu}" = "--cuda" ]; then
    make -C native_client/javascript clean npm-pack PROJECT_NAME=deepspeech-gpu
  else
    make -C native_client/javascript clean npm-pack
  fi

  tar -czf native_client/javascript/wrapper.tar.gz \
    -C native_client/javascript/ lib/
}

do_deepspeech_npm_package()
{
  package_option=$1

  cd ${DS_DSDIR}

  npm update

  # Python 2.7 is required for node-pre-gyp, it is only required to force it on
  # Windows
  if [ "${OS}" = "${TC_MSYS_VERSION}" ]; then
    NPM_ROOT=$(cygpath -u "$(npm root)")
    PYTHON27=":/c/Python27"
    # node-gyp@5.x behaves erratically with VS2015 and MSBuild.exe detection
    npm install node-gyp@4.x node-pre-gyp
  else
    NPM_ROOT="$(npm root)"
    npm install node-gyp@5.x node-pre-gyp
  fi

  export PATH="$NPM_ROOT/.bin/$PYTHON27:$PATH"

  all_tasks="$(curl -s https://community-tc.services.mozilla.com/api/queue/v1/task/${TASK_ID} | python -c 'import json; import sys; print(" ".join(json.loads(sys.stdin.read())["dependencies"]));')"

  for dep in ${all_tasks}; do
    curl -L https://community-tc.services.mozilla.com/api/queue/v1/task/${dep}/artifacts/public/wrapper.tar.gz | tar -C native_client/javascript -xzvf -
  done;

  if [ "${package_option}" = "--cuda" ]; then
    make -C native_client/javascript clean npm-pack PROJECT_NAME=deepspeech-gpu
  elif [ "${package_option}" = "--tflite" ]; then
    make -C native_client/javascript clean npm-pack PROJECT_NAME=deepspeech-tflite
  else
    make -C native_client/javascript clean npm-pack
  fi
}

do_bazel_build()
{
  cd ${DS_ROOT_TASK}/DeepSpeech/tf
  eval "export ${BAZEL_ENV_FLAGS}"

  if is_patched_bazel; then
    find ${DS_ROOT_TASK}/DeepSpeech/tf/bazel-out/ -iname "*.ckd" | tar -cf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-tf.tar -T -
  fi;

  bazel ${BAZEL_OUTPUT_USER_ROOT} build \
    -s --explain bazel_monolithic.log --verbose_explanations --experimental_strict_action_env --workspace_status_command="bash native_client/bazel_workspace_status_cmd.sh" --config=monolithic -c opt ${BAZEL_BUILD_FLAGS} ${BAZEL_TARGETS}

  if is_patched_bazel; then
    find ${DS_ROOT_TASK}/DeepSpeech/tf/bazel-out/ -iname "*.ckd" | tar -cf ${DS_ROOT_TASK}/DeepSpeech/bazel-ckd-ds.tar -T -
  fi;

  verify_bazel_rebuild "${DS_ROOT_TASK}/DeepSpeech/tf/bazel_monolithic.log"
}

shutdown_bazel()
{
  cd ${DS_ROOT_TASK}/DeepSpeech/tf
  bazel ${BAZEL_OUTPUT_USER_ROOT} shutdown
}

do_deepspeech_binary_build()
{
  cd ${DS_DSDIR}
  make -C native_client/ \
    TARGET=${SYSTEM_TARGET} \
    TFDIR=${DS_TFDIR} \
    RASPBIAN=${SYSTEM_RASPBIAN} \
    EXTRA_CFLAGS="${EXTRA_LOCAL_CFLAGS}" \
    EXTRA_LDFLAGS="${EXTRA_LOCAL_LDFLAGS}" \
    EXTRA_LIBS="${EXTRA_LOCAL_LIBS}" \
    deepspeech${PLATFORM_EXE_SUFFIX}
}

do_deepspeech_ndk_build()
{
  arch_abi=$1

  cd ${DS_DSDIR}/native_client/

  ${ANDROID_NDK_HOME}/ndk-build \
    APP_PLATFORM=android-21 \
    APP_BUILD_SCRIPT=$(pwd)/Android.mk \
    NDK_PROJECT_PATH=$(pwd) \
    APP_STL=c++_shared \
    TFDIR=${DS_TFDIR} \
    TARGET_ARCH_ABI=${arch_abi}
}

do_deepspeech_netframework_build()
{
  cd ${DS_DSDIR}/native_client/dotnet

  # Setup dependencies
  nuget install DeepSpeechConsole/packages.config -OutputDirectory packages/

  MSBUILD="$(cygpath 'C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\MSBuild.exe')"

  # We need MSYS2_ARG_CONV_EXCL='/' otherwise the '/' of CLI parameters gets mangled and disappears
  # We build the .NET Client for .NET Framework v4.5,v4.6,v4.7

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.5.2" \
    /p:OutputPath=bin/nuget/x64/v4.5

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.6" \
    /p:OutputPath=bin/nuget/x64/v4.6

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechClient/DeepSpeechClient.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:TargetFrameworkVersion="v4.7" \
    /p:OutputPath=bin/nuget/x64/v4.7

  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechConsole/DeepSpeechConsole.csproj \
    /p:Configuration=Release \
    /p:Platform=x64
}

do_deepspeech_netframework_wpf_example_build()
{
  cd ${DS_EXAMPLEDIR}/net_framework

  # Setup dependencies
  nuget install DeepSpeechWPF/packages.config -OutputDirectory DeepSpeechWPF/packages/

  MSBUILD="$(cygpath 'C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\MSBuild.exe')"

  # We need MSYS2_ARG_CONV_EXCL='/' otherwise the '/' of CLI parameters gets mangled and disappears
  # Build WPF example
  MSYS2_ARG_CONV_EXCL='/' "${MSBUILD}" \
    DeepSpeechWPF/DeepSpeech.WPF.csproj \
    /p:Configuration=Release \
    /p:Platform=x64 \
    /p:OutputPath=bin/x64

}

do_nuget_build()
{
  PROJECT_NAME=$1
  if [ -z "${PROJECT_NAME}" ]; then
    exit "Please call with a valid PROJECT_NAME"
    exit 1
  fi;

  cd ${DS_DSDIR}/native_client/dotnet

  cp ${DS_TFDIR}/bazel-bin/native_client/libdeepspeech.so nupkg/build

  # We copy the generated clients for .NET into the Nuget framework dirs

  mkdir -p nupkg/lib/net45/
  cp DeepSpeechClient/bin/nuget/x64/v4.5/DeepSpeechClient.dll nupkg/lib/net45/

  mkdir -p nupkg/lib/net46/
  cp DeepSpeechClient/bin/nuget/x64/v4.6/DeepSpeechClient.dll nupkg/lib/net46/

  mkdir -p nupkg/lib/net47/
  cp DeepSpeechClient/bin/nuget/x64/v4.7/DeepSpeechClient.dll nupkg/lib/net47/

  PROJECT_VERSION=$(strip "${DS_VERSION}")
  sed \
    -e "s/\$NUPKG_ID/${PROJECT_NAME}/" \
    -e "s/\$NUPKG_VERSION/${PROJECT_VERSION}/" \
    nupkg/deepspeech.nuspec.in > nupkg/deepspeech.nuspec && cat nupkg/deepspeech.nuspec

  nuget pack nupkg/deepspeech.nuspec
}
