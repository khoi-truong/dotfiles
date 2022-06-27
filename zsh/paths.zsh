# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export PATH="/usr/local/sbin:$PATH"

export GOPATH="$HOME/Code/go"
export GOBIN="$GOPATH/bin"
export PATH=$GOPATH:$PATH
export PATH=$GOBIN:$PATH

export PATH="$HOME/.cargo/bin:$PATH"

export PATH="$HOME/.config/carthage/bin:$PATH"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"

export PATH="$HOME/.jenv/bin:$PATH"
