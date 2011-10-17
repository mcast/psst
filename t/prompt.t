#! perl
use strict;
use warnings;
use Test::More tests => 5;

use lib 't/tlib';
use BashRunner 'bash_interactive';


sub main {
  $ENV{PATH} = "blib/script:$ENV{PATH}"; # not set by prove or Makefile.PL

  # prevent influence from real local::lib
  my @LLvars = qw{PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT MODULEBUILDRC};
  delete @ENV{@LLvars};

  prompt_tt(); # 2
  pidburn_tt(); # 3
}


sub prompt_tt {
  local $ENV{HOME} = 't/home-ps1';
  local $ENV{PS1_FROM_TEST} = 'here> '; # nb. trailing space is lost in bashrc
  # because we allow absence of that arg

  # getting initialised...  --rcfile t/bashrc doesn't?
  my $run = qq{. t/bashrc\necho showvar::\$BASHRC_FOR_TESTING::\n};
  like(bash_interactive($run),
       qr{^here>echo.*\nshowvar::seen::\nhere>exit\n\z}m,
       'see our bashrc, use our prompt');

  delete $ENV{PS1_FROM_TEST};
  like(bash_interactive($run), qr{^cfgd> echo}m, 'take PS1_old from home-ps1');
}


sub pidburn_tt {
  # does Bash burn pids?
 SKIP: {
    my $pidseq = pidseq_subtest();
    skip 'pid allocation appears to be randomised', 3
      if $pidseq =~ /^rand/;

    like($pidseq, qr{^sequential=1 }, 'Bash does not burn PIDs');
    local $ENV{PERL_LOCAL_LIB_ROOT} = '/path/to/foo:/path/to/bar';
  TODO: {
      local $TODO = 'not implemented in psst(1)';
      like(pidseq_subtest(), qr{^sequential=1 },
	   "don't burn pids unless PS1_substs");
    }
    local $ENV{HOME} = 't/home-substing';
    like(pidseq_subtest(), qr{^promptburn=2 },
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
  my $N = 50;

  # print many prompts, examine pid issued to the process requested
  my $run = ". t/bashrc\n".("perl -e 'print qq{pid:\$\$\\n}'\n" x $N);
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

  $N --; # we are now interested in differences between PIDs; sample of these is smaller
  my @hist; # output elements
  my @diff_sig; # $diff which are significant
  my $thres = sqrt($N);
  foreach my $diff (sort {$hist{$b} <=> $hist{$a}} keys %hist) {
    my $count = $hist{$diff};
    my $sig = $count / $thres;
    $count .= "/$N" if !@hist; # show total on first ele
    my $ele = $sig > 1 ? "$diff <$count>" : "($diff x$count)";
    push @diff_sig, $diff if $sig > 1;
    push @hist, $ele;
  }
  my $raw = join ', ', @hist;
  $raw .= sprintf('; thres=%.2f', $thres);

  # Summarise
  if (0 == @diff_sig) {
    return "random: $raw";
  } elsif (1 == @diff_sig) {
    my $diff = $diff_sig[0];
    my $type = { 1 => 'sequential', 2 => 'promptburn' }->{$diff} || 'weird';
    return "$type=$raw";
  } else {
    return "weird (not unimodal..  not enough trials? system busy?): $raw";
  }
}


sub deansi {
  my ($txt) = @_;
  $txt =~ s{\x1b(\][0-9;]*m)}{}g;
  return $txt;
}


main();
