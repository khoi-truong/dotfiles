# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export GOPATH="$HOME/Code/go"
export GOBIN="$GOPATH/bin"
export PATH=$PATH:$GOPATH
export PATH=$PATH:$GOBIN

export PATH=$PATH:"$HOME/.cargo/bin"

export PATH=$PATH:"$HOME/.config/carthage/bin"

export PYENV_ROOT="$HOME/.pyenv"
export PATH=$PATH:"$PYENV_ROOT/bin"
eval "$(pyenv init --path)"
