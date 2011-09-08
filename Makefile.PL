#! /usr/bin/env perl
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile
  (NAME           => 'App::psst',
   VERSION_FROM => 'lib/App/psst.pm',
   ABSTRACT_FROM  => 'lib/App/psst.pm',
   EXE_FILES => [qw[ script/psst ]],

   LICENSE => 'perl',

   PREREQ_PM => { 'local::lib' => '1.008' }, # for PERL_LOCAL_LIB_ROOT

   MIN_PERL_VERSION => '5.006', # probably

   META_MERGE =>
   {
    author => [ 'Matthew Astley <mca1001@users.sourceforge.net>' ],

    resources =>
    {
     homepage => 'https://github.com/mca-wtsi/psst',
     Repository => # data per spec2; subkey conforms to spec 1.4
     {
      url => 'git@github.com:mca-wtsi/psst.git',
      web => 'https://github.com/mca-wtsi/psst',
      type => 'git',
     },
     # bugtracker => none
    },

    optional_features =>
    { config => { description => 'Ability to read ~/.psst.yaml',
		  requires => { YAML => '0.71' } },
    },

   });
