#! perl
use strict;
use warnings;
use Test::More tests => 20;
use POSIX ":sys_wait_h";
use Time::HiRes qw( gettimeofday tv_interval ualarm );

sub main {
  $ENV{PATH} = "blib/script:$ENV{PATH}"; # not set by prove or Makefile.PL

  preconds_tt(); # 9
  histzap_tt(); # 2
  interactiveness_tt(); # 4
  prompt_tt(); # 5
}


sub preconds_tt {
  # see that we're talking to something we understand
  my $bash_version_txt = `bash --version`;
  my ($bash_version) =
    ($bash_version_txt =~ qr{\bbash\b.* version ([-0-9.]+\S)});
  like($bash_version, qr{^([3-9]|\d{2,})\.\d+}, # >= v3 is a guess
       "bash --version: sane and modern-ish");

  foreach my $k (qw( POSIXLY_CORRECT PROMPT_COMMAND PROMPT_DIRTRIM )) {
    ok(!defined $ENV{$k}, "Bash with \$$k is untested, YMMV");
  }

  # can we find ourself with both hands?
  foreach my $fn (qw( blib/script/psst t/prompt.t )) {
    ok(-f $fn, "$fn is a file");
  }
  is(devino($0), devino('t/prompt.t'), 'running in there');

  # need our built copy on PATH, PERL5LIB
#  like($ENV{PATH}, qr{^[^:]*blib/script/?(:|$)}, 'our blib on $ENV{PATH}');
# hardwired above
  like((join ':', @INC), qr{^[^:]*blib/lib/?(:|$)}, 'our blib on @INC');
  like($ENV{PERL5LIB}, qr{^[^:]*blib/lib/?(:|$)}, 'our blib on $ENV{PERL5LIB}');
}

sub histzap_tt {
  # ensure we are not polluting user's history file
  my $histfn = "$ENV{HOME}/.bash_history";
  my $pid = $$;

  like(bash_interactive("echo 'disTincTivecanarycommand+$pid from $0'"),
       qr{^disTincTive.*$pid\b}m, "ran history canary");

 SKIP: {
    skip "no $histfn", 1 unless -f $histfn;
    if (open my $fh, '<', $histfn) {
      my @hit;
      while (<$fh>) {
	push @hit, $_ if /disTincTivecanarycommand.*$pid/;
      }
      is("@hit", '', "$histfn not polluted");
    } else{
      fail("read $histfn: $!");
    }
  }
}

sub interactiveness_tt {
  # see that &bash_interactive works

  is(bash_interactive("echo \$PPID\n", PS1 => '>'),
     qq{>echo \$PPID\n$$\n>exit\n}, "PPID check");

  my $quick_alarm = 0.75; # too quick will cause false fail; slow is tedious
  my $t0 = [gettimeofday()];
  my $ans = eval { bash_interactive("sleep 7", maxt => $quick_alarm) } || $@;
  my $wallclock = tv_interval($t0);
  like($ans, qr{Timeout.*waiting for}, "ualarm fired (total $wallclock sec)");
  cmp_ok($wallclock, '>', $quick_alarm * 0.7, 'ualarm waited');

  local @ENV{qw{ G1 G2 G3 }} =
    ('ABCD goldfish', 'MA goldfish', 'SAR CDBDIs');
  like(bash_interactive(qq{echo \$G1; echo \$G2\necho \$G3\n}),
       qr{ABCD.*MA.*SAR}s, "command sequence");
}


sub prompt_tt {
  local $ENV{HOME} = 't/home-ps1';
  local $ENV{PS1_FROM_TEST} = 'here> '; # nb. trailing space is lost in bashrc
  # because we allow absence of that arg

  # prevent influence from real local::lib
  my @LLvars = qw{PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT MODULEBUILDRC};
  local @ENV{@LLvars};
  delete @ENV{@LLvars};

  # getting initialised...  --rcfile t/bashrc doesn't?
  my $run = qq{. t/bashrc\necho showvar::\$BASHRC_FOR_TESTING::\n};
  like(bash_interactive($run),
       qr{^here>echo.*\nshowvar::seen::\nhere>exit\n\z}m,
       'see our bashrc, use our prompt');

  delete $ENV{PS1_FROM_TEST};
  like(bash_interactive($run), qr{^cfgd> echo}m, 'take PS1_old from home-ps1');

  # does Bash burn pids?
 SKIP: {
    my $pidseq = pidseq_subtest($run);
    skip 'pid allocation appears to be randomised', 3
      if $pidseq =~ /^rand/;

    like($pidseq, qr{^sequential=1 }, 'Bash does not burn PIDs');
    local $ENV{PERL_LOCAL_LIB_ROOT} = '/path/to/foo:/path/to/bar';
  TODO: {
      local $TODO = 'not implemented in psst(1)';
      like(pidseq_subtest($run), qr{^sequential=1 },
	   "don't burn pids unless PS1_substs");
    }
    local $ENV{HOME} = 't/home-substing';
    like(pidseq_subtest($run), qr{^promptburn=2 },
	 'it seems we must burn pids to do PS1_substs');
  }
}


# Attempt to determine whether the shell is forking per prompt.
# Likely to be flaky.
#
# Likely outcomes,
#   broken: can't see pids
#   sequential=1 <n>: Perl eats one per line
#   promptburn=2 <n>: Bash & Perl each eat one per line
#   random: no discernable pattern (e.g. on OpenBSD)
#
# PID wrap should not cause problems.  Fast PID churn from other
# sources might require larger $N to get non-weird results.
sub pidseq_subtest {
  my ($base_run) = @_;
  my $N = 50;

  # print many prompts, examine pid issued to the process requested
  my $run = $base_run.("perl -e 'print qq{pid:\$\$\\n}'\n" x $N);
  my $txt = bash_interactive($run, maxt => $N / 5);

  my @pid = ($txt =~ m{^pid:(\d+)$}mg);
  if ($N != @pid) {
    return sprintf('broken: see %d/%d pid: lines', scalar @pid, $N);
  }

  # Very basic stats.  Output elements are
  #
  #   "$diff1 <$count_significant>"
  #   "($diff2 x$count_insignificant)"
  my %hist; # key = line-to-line difference in PID; value = event count
  while ($#pid) {
    my $diff = $pid[1] - (shift @pid);
    $hist{$diff} ++;
  }
  my @hist; # output elements
  my @diff_sig; # $diff which are significant
  foreach my $diff (sort {$hist{$b} <=> $hist{$a}} keys %hist) {
    my $count = $hist{$diff};
    my $sig = $count / sqrt($N);
    $count .= '/'.($N-1) if !@hist; # show total on first ele
    my $ele = $sig > 1 ? "$diff <$count>" : "($diff x$count)";
    push @diff_sig, $diff if $sig > 1;
    push @hist, $ele;
  }
  my $raw = join ', ', @hist;

  # Summarise
  if (0 == @diff_sig) {
    return "random: $raw";
  } elsif (1 == @diff_sig) {
    my $diff = $diff_sig[0];
    my $type = { 1 => 'sequential', 2 => 'promptburn' }->{$diff} || 'weird';
    return "$type=$raw";
  } else {
    return "weird (not unimodal): $raw";
  }
}


# %arg keys
#   PS1 => set in %ENV
#   maxt => alarm timeout/sec, default 5
sub bash_interactive {
  my ($in, %arg) = @_;

  my $maxt = delete $arg{maxt} || 5;

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
  ualarm($maxt * 1E6);

  my $out = join '', <$shout_fh>;
  close $shout_fh;
  $out .= sprintf("\nRETCODE:0x%02x\n", $?) if $?;

  ualarm(0);

  # wait on writer, for tidiness
  while ((my $done = waitpid(-1, WNOHANG)) > 0) {
    warn "something on pid=$done (probably a writer) failed ?=$?" if $?;
  }

  return $out;
}

sub devino {
  my ($fn) = @_;
  my @s = stat($fn);
  return @s ? "$s[0]:$s[1]" : "$fn absent";
}

sub deansi {
  my ($txt) = @_;
  $txt =~ s{\x1b(\][0-9;]*m)}{}g;
  return $txt;
}


main();
