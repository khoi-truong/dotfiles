# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export PATH=$PATH:/usr/local/bin
export PATH=$PATH:/usr/local/sbin
export PATH=$PATH:/opt/homebrew/bin
export PATH=$PATH:/opt/homebrew/sbin

export GOPATH=$HOME/Code/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN:$GOPATH

export PATH=$PATH:$HOME/.cargo/bin

export PATH=$PATH:$HOME/.config/carthage/bin

export PYENV_ROOT=$HOME/.pyenv
export PATH=$PATH:$PYENV_ROOT/bin
eval "$(pyenv init --path)"

export PATH=$PATH:$HOME/.jenv/bin

# Android SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME

# Flutter
export PATH=$PATH:$HOME/.pub-cache/bin
export FVM_HOME="$HOME/.fvm"

# Pipx
export PATH=$PATH:/Users/khoi/.local/bin
