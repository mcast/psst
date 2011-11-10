package BashRunner;
use strict;
use warnings;

use POSIX ":sys_wait_h";
use Time::HiRes qw( alarm );
use base 'Exporter';

our @EXPORT_OK = qw( bash_interactive );


# %arg keys
#   PS1 => set in %ENV
#   maxt => alarm timeout/sec, default 5
#   raw => don't strip off job control warning
sub bash_interactive {
  my ($in, %arg) = @_;

  my $maxt = delete $arg{maxt} || 5;
  my $raw = delete $arg{raw} || 0;

  local $ENV{PS1};
  if (defined $arg{PS1}) {
    $ENV{PS1} = delete $arg{PS1};
  } else {
    delete $ENV{PS1};
  }

  local $ENV{HISTFILE} = undef;
  local $ENV{IGNOREEOF};
  delete $ENV{IGNOREEOF};

  my @cmd = qw( bash --noprofile --norc -i );

  my @left = sort keys %arg;
  die "unknown %arg keys @left" if @left;

  pipe(my $read_fh, my $write_fh);
  #
  #  this test process
  #    \-- write $in to pipe
  #    \-- bash <( pipe ) | test process

  # Writer subprocess: send $in down the pipe
  my $wr_pid = fork();
  die "fork() for writer failed: $!" unless defined $wr_pid;
  if (!$wr_pid) {
    # child - do the writing
    close $read_fh;
    print $write_fh $in;
    exit 0;
  }

  # Reader subprocess, eventually becomes the shell
  my $rd_pid = open my $shout_fh, "-|";
  die "fork() for shell failed: $!" unless defined $rd_pid;
  if (!$rd_pid) {
    # child - connect pipe to shell
    close $write_fh;
    open STDERR, '>&', \*STDOUT
      or die "Can't dup STDERR into STDOUT: $!";
    open STDIN, '<&', \*$read_fh
      or die "Can't dup STDIN from pipe: $!";
    exec @cmd or die "exec(@cmd) failed: $!";
  }
  close $write_fh;
  close $read_fh;

  local $SIG{ALRM} = sub {
    kill 'HUP', $rd_pid; # kick the shell on our way out
    die "Timeout(${maxt}s) waiting for @cmd";
  };
  alarm($maxt);

  my $out = join '', <$shout_fh>;
  close $shout_fh;
  $out .= sprintf("\nRETCODE:0x%02x\n", $?) if $?;

  alarm(0);

  # wait on writer, for tidiness
  while ((my $done = waitpid(-1, WNOHANG)) > 0) {
    warn "something on pid=$done (probably a writer) failed ?=$?" if $?;
  }

  # remove job control warning (no tty, e.g. under "ssh -T")
  unless ($raw || -t STDIN) {
    # XXX: a localisation disaster?
    $out =~ s{\Abash: no job control in this shell\n}{};
  }

  return $out;
}

1;
