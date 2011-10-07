
use strict;
use warnings;

use 5.006;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "prompt string setting tool",
  "AUTHOR" => "Matthew Astley <mca1001\@users.sourceforge.net>",
  "BUILD_REQUIRES" => {
    "Test::More" => 0,
    "Time::HiRes" => "1.9713"
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "App-psst",
  "EXE_FILES" => [
    "script/psst"
  ],
  "LICENSE" => "perl",
  "NAME" => "App::psst",
  "PREREQ_PM" => {
    "local::lib" => "1.008"
  },
  "VERSION" => "0.003010",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



