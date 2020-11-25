#!usr/bin/perl
use warnings;
use strict;
use autodie;

use LWP 5.64;
use JSON;
use Time::Local;
use Data::Dumper;
use DateTime;


my @Fixtures = ();
my $currentTime = time();
my $browser = LWP::UserAgent->new;

#Set up base url and parameters to be passed to API
my $baseURL = 'https://api-football-v1.p.rapidapi.com/v2/';
my @headers = (
    'x-rapidapi-host' => 'api-football-v1.p.rapidapi.com',
	'x-rapidapi-key' => '###########################',
	'useQueryString' => 'true',
);

#Get config rules
open my $fh, '<', "/kunden/homepages/18/d821901708/htdocs/David/fixtures/config.json" or die "Can't open file $!";
read $fh, my $file_content, -s $fh;
close $fh;
my $config = decode_json($file_content);


#Add fixtures for each team in config
foreach (@{$config->{"Team"}}) {
    my $teamURL = "${baseURL}fixtures/team/${_}/next/5";
    my $jsonResponse = decode_json($browser->get($teamURL, @headers)->content());
    foreach (@{$jsonResponse->{"api"}->{"fixtures"}}) {
        addFixture($_);
    }
}

#Add fixtures for each full league in config
foreach (@{$config->{"FullLeague"}}) {
    my $leagueURL = "${baseURL}fixtures/league/${_}?timezone=Europe/London";
    my $jsonResponse = decode_json($browser->get($leagueURL, @headers)->content());
    foreach (@{$jsonResponse->{"api"}->{"fixtures"}}) {
        addFixture($_);
    }
}


#Add fixtures for each league in config.
foreach my $key (keys(%{$config->{"League"}})) {
    my $leagueID = $key;
    my $leagueConfig = $config->{"League"}->{$key};
    my $standingsURL;
    my $standingsResponse;
    my @topTeams;
    
    #If we only want top teams then get current standings and store in topTeams array.
    if (defined($leagueConfig->{"Top"})) {
        $standingsURL = "${baseURL}leagueTable/${leagueID}";
        $standingsResponse = decode_json($browser->get($standingsURL, @headers)->content());
        foreach my $team (@{$standingsResponse->{"api"}->{"standings"}->[0]}) {
            if ($team->{"rank"} <= $leagueConfig->{"Top"}) {
                push(@topTeams, $team->{"team_id"});
            }
        }
    }
    
    my $fixturesURL = "${baseURL}fixtures/league/${leagueID}?timezone=Europe/London";
    my $fixturesResponse = decode_json($browser->get($fixturesURL, @headers)->content());
    
    #For each fixture check if we want it
    foreach (@{$fixturesResponse->{"api"}->{"fixtures"}}) {
        my $fixture = $_;
        #Add if both teams are ranked high enough
        if (@topTeams) {
            my $teamsInTop = 0;
            foreach my $team (@topTeams) {
                if (($team eq $fixture->{"homeTeam"}->{"team_id"}) || ($team eq $fixture->{"awayTeam"}->{"team_id"})) {
                    $teamsInTop++;
                }
            }
            if ($teamsInTop == 2) {
                addFixture($fixture);
            }
        }
        
        #Add if round is in config
        if (defined($leagueConfig->{"Round"})) {
            foreach my $round (@{$leagueConfig->{"Round"}}) {
                if ($round eq $fixture->{"round"}) {
                    addFixture($fixture);
                }
            }
        }
        
        #Add if both teams are specified in config
        foreach my $teams (@{$leagueConfig->{"Teams"}}){
            my $teamsInTeams = 0;
            foreach my $team (@{$teams}) {
                if (($team eq $fixture->{"homeTeam"}->{"team_id"}) || ($team eq $fixture->{"awayTeam"}->{"team_id"})) {
                    $teamsInTeams++;
                }
            }
            if ($teamsInTeams == 2) {
                addFixture($fixture);
            }
        }   
    }
}

#Check for dupes and add
sub addFixture {
    my $fixture = $_[0];
    my $isDupe = 0;
    foreach (@Fixtures) {
        if ($_->{"fixture_id"} eq $fixture->{"fixture_id"}) {
            $isDupe = 1;
            last;
        }
    }
    if (!$isDupe && isFixtureInRange($fixture->{"event_date"})) {
        push(@Fixtures, $fixture);
    }
}

#Returns true if given date is in range
sub isFixtureInRange {
    my ($yyyy, $MM, $dd, $hh, $mm, $ss) = ($_[0] =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/);
    my $fixtureTime = timelocal($ss, $mm, $hh, $dd, $MM - 1, $yyyy);
    my $fixtureTimeInDays = ($fixtureTime - $currentTime) / (60 * 60 * 24);
    if ($fixtureTimeInDays > 0 && $fixtureTimeInDays < $config->{"daysOfGames"}) {
        return 1;
    }
    return 0;
}

@Fixtures = sort {$a->{"event_date"} cmp $b->{"event_date"}} @Fixtures;

#Add nicely formatted date and time fields to fixture array
foreach my $fixture (@Fixtures) {
    my ($yyyy, $MM, $dd, $hh, $mm, $ss) = ($fixture->{"event_date"} =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/);
    my $dt = DateTime->new(year => $yyyy, month => $MM, day => $dd);
    $fixture->{"date"} = $dt->day_name . ' ' . $dd . ' ' .  $dt->month_name;
    $fixture->{"time"} = $hh . ':' . $mm;
}

my $jsonFixtures = encode_json(\@Fixtures);
open (my $FH, '>', "/kunden/homepages/18/d821901708/htdocs/David/fixtures/fixtures.json");
print $FH $jsonFixtures;
close($FH);
