my @args = ( 'cat -n ~/Documents/myarch/TokenCODE | sed -n 9p ~/Documents/myarch/TokenCODE | xclip -selection "clipboard" -rmlastnl' );

exec @args;               # subject to shell escapes
                            # if @args == 1
exec { $args[0] } @args;  # safe even with one-arg list
