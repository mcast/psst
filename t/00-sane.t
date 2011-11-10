#! perl
use strict;
use warnings;

END {
  # must be before Test::More's END blocks
  BAIL_OUT('Sanity checks failed') if $?;
}
use Test::More tests => 17;

use Time::HiRes qw( gettimeofday tv_interval );

use lib 't/tlib';
use BashRunner 'bash_interactive';


sub main {
  preconds_tt(); # 11
  histzap_tt(); # 2
  interactiveness_tt(); # 4
}


sub preconds_tt {
  # see that we're talking to something we understand
  my $bash_version_txt = `bash --version`;
  my ($bash_version) =
    ($bash_version_txt =~ qr{\bbash\b.* version (.*)});
  like($bash_version, qr{^([2-9]|\d{2,})\.\d+}, # >= v2 is a guess
       "bash --version: sane and modern-ish") &&
	 diag("bash --version: $bash_version");

  # Need HOME for the "history not polluted" check
  # Need PATH during PATH-munge in later tests
  foreach my $k (qw( HOME PATH )) {
    ok(defined $ENV{$k} && $ENV{$k} ne '', "\$$k is set");
  }

  foreach my $k (qw( POSIXLY_CORRECT PROMPT_COMMAND PROMPT_DIRTRIM )) {
    ok(!defined $ENV{$k}, "Bash with \$$k is untested, YMMV");
  }

  # can we find ourself with both hands?
  foreach my $fn (qw( blib/script/psst t/prompt.t )) {
    ok(-f $fn, "$fn is a file");
  }
  is(devino($0), devino('t/00-sane.t'), 'running in there');

  # need our built copy on PATH, PERL5LIB
#  like($ENV{PATH}, qr{^[^:]*blib/script/?(:|$)}, 'our blib on $ENV{PATH}');
# hardwired above
  like((join ':', @INC), qr{^(t/tlib:)?[^:]*blib/lib/?(:|$)}, 'our blib on @INC');
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


sub devino {
  my ($fn) = @_;
  my @s = stat($fn);
  return @s ? "$s[0]:$s[1]" : "$fn absent";
}


main();
