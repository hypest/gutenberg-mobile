FROM gitpod/workspace-full

ENV ANDROID_SDK_ROOT=/usr/lib/android-sdk

ARG cmd_line_tools_version=6858069
ARG cmd_line_tools_zip_name="commandlinetools-linux-"$cmd_line_tools_version"_latest.zip"
ARG cmdline_tools_root=$ANDROID_SDK_ROOT/cmdline-tools
ARG cmdline_tools_location=$cmdline_tools_root/latest
ARG sdkmanager_bin=$cmdline_tools_location/bin/sdkmanager
ARG build_tools_version="29.0.2"
ARG platform_version="28"

# Install custom tools, runtime, etc.
RUN sudo apt update \
    && sudo apt install -y qrencode \
    && wget http://www.home.unix-ag.org/simon/woof && chmod +x woof && sudo mv woof /usr/local/bin/ \
    && curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.38.0/install.sh | bash \
    && export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
    && sudo apt install -y android-sdk \
    && wget https://dl.google.com/android/repository/$cmd_line_tools_zip_name \
    && unzip $cmd_line_tools_zip_name \
    && sudo mkdir $cmdline_tools_root \
    && sudo mv ./cmdline-tools $cmdline_tools_location \
    && yes | sudo $sdkmanager_bin --install "build-tools;$build_tools_version" \
    && yes | sudo $sdkmanager_bin --install "platforms;android-$platform_version" \
    && yes | sudo $sdkmanager_bin --install "platforms;android-29" \
    && yes | sudo $sdkmanager_bin --licenses

ENV PATH=$PATH:$cmdline_tools_location/bin/
