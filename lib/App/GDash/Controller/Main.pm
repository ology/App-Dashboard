package App::GDash::Controller::Main;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Capture::Tiny qw(capture);
use Data::Dumper::Compact qw(ddc);
use Encoding::FixLatin qw(fix_latin);
use HTTP::Simple qw(getstore);
use List::Util qw(first);
use Mojo::DOM ();
use Storable qw(retrieve store);
use XML::RSS ();

use App::GDash::Controller::Command qw(rss_cmd perl_cmd curl_cmd);

use constant DASHFILE => 'dashboard.dat';
use constant WIDTHS   => [4, 6, 8, 12];

sub index ($self) {
  my $cards;
  if (-e DASHFILE) {
    $cards = retrieve DASHFILE;
  }
  else {
    $cards = {
      1 => {id=>1,pos=>1,width=>8,title=>'A',text=>'Foo!'},
      2 => {id=>2,pos=>2,width=>4,title=>'B',text=>'Bar?'},
      3 => {id=>3,pos=>3,width=>6,title=>'C',text=>'Baz...'},
      4 => {id=>4,pos=>4,width=>6,title=>'D',text=>'Derp'},
    };
    store($cards, DASHFILE);
  }
  $self->render(
    cards  => $cards,
    max    => 12,
    min    => 4,
    widths => WIDTHS,
  );
}

sub update ($self) {
  unless (-e DASHFILE) {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $cards = retrieve DASHFILE;
  my $v = $self->validation;
  $v->required('cardId')->like(qr/^\d+$/);
  $v->required('cardTitle')->size(1, 50);
  $v->required('cardText')->size(1, 1024);
  $v->required('cardPosition')->in(1 .. keys %$cards);
  $v->required('cardWidth')->in(WIDTHS->@*);
  if ($v->error('cardId')
    || $v->error('cardTitle') || $v->error('cardText')
    || $v->error('cardPosition') || $v->error('cardWidth')
  ) {
    $self->flash(error => 'Invalid update');
    return $self->redirect_to('index');
  }
  my $id  = $v->param('cardId');
  my $pos = $v->param('cardPosition');
  if ($cards->{$id}{pos} != $pos) {
    my @by_id = sort { $cards->{$a}{pos} <=> $cards->{$b}{pos} } keys %$cards;
    my @reordered;
    my $n = 0;
    for my $i (@by_id) {
      $n++;
      next                 if $i == $id;
      push @reordered, $i  if $pos > $cards->{$id}{pos};
      push @reordered, $id if $n == $pos;
      push @reordered, $i  if $pos < $cards->{$id}{pos};
    }
    $n = 0;
    for my $i (@reordered) {
      $n++;
      $cards->{$i}{pos} = $n;
    }
  }
  $cards->{$id}{title} = $v->param('cardTitle');
  $cards->{$id}{text}  = $v->param('cardText');
  $cards->{$id}{width} = $v->param('cardWidth');

  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub refresh ($self) {
  my $v = $self->validation;
  $v->required('cardId')->like(qr/^\d+$/);
  if ($v->error('cardId')) {
    $self->flash(error => 'Invalid refresh');
    return $self->redirect_to('index');
  }
  unless (-e DASHFILE) {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $cards = retrieve DASHFILE;
  my $id = $v->param('cardId');
  if ($cards->{$id}{text} =~ /^rss:(.+)$/) {
    my $feed = $1;
    my $rss_content = 'rss-content.xml';
    unlink $rss_content;
    _get_file($feed, $rss_content);
    if (-e $rss_content) {
      my $rss = XML::RSS->new;
      eval { $rss->parsefile($rss_content) };
      if ($@) {
        warn "Can't parse $rss_content: $@\n";
      }
      else {
        my $content = '<ul>';
        my $n = 0;
        for my $item ($rss->{items}->@*) {
          $n++;
          my $text = $item->{title};
          unless ($text) {
            my $dom = Mojo::DOM->new($item->{description});
            $text = $dom->all_text;
            $text = substr($text, 0, 49) . '...';
          }
          $content .= qq|<li><a href="$item->{link}" target="_blank">$text</a></li>|;
          last if $n >= 20;
        }
        $content .= '</ul>';
        $cards->{$id}{content} = $content;
      }
    }
  }
  elsif ($cards->{$id}{text} =~ /^perl:(.+)$/) {
    my $command = "perl -Mojo -E'$1'";
    return 'Invalid' if $command =~ /\bsystem\b/;
    my ($stdout, $stderr, $exit) = capture { system($command) };
    chomp $stdout;
    $cards->{$id}{content} = $stderr ? $stderr : $stdout;
  }
  elsif ($cards->{$id}{text} =~ /^curl:(.+)$/) {
    my $command = "curl $1";
    my ($stdout) = capture { system($command) };
    chomp $stdout;
    $cards->{$id}{content} = fix_latin($stdout);
  }
  else {
    delete $cards->{$id}{content} if exists $cards->{$id}{content};
  }
  store($cards, DASHFILE);
  $self->render(text => ($cards->{$id}{content} || $cards->{$id}{text}))
}

sub _get_file {
    my ($url, $file) = @_;
    my $status = getstore($url, $file)
        or warn "Can't getstore $url to $file: $!\n";
    warn "Could not get $file from $url\n"
        unless $status == 200;
}

sub delete ($self) {
  my $v = $self->validation;
  $v->required('cardId')->like(qr/^\d+$/);
  if ($v->error('cardId')) {
    $self->flash(error => 'Invalid update');
    return $self->redirect_to('index');
  }
  unless (-e DASHFILE) {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $cards = retrieve DASHFILE;
  my $id = $v->param('cardId');
  delete $cards->{$id} if exists $cards->{$id};
  my @by_id = sort { $cards->{$a}{pos} <=> $cards->{$b}{pos} } keys %$cards;
  my $n = 0;
  for my $i (@by_id) {
    $n++;
    $cards->{$i}{pos} = $n;
  }
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub new_card ($self) {
  my $v = $self->validation;
  $v->required('cardTitle')->size(1, 50);
  $v->required('cardText')->size(1, 1024);
  $v->required('cardWidth')->in(WIDTHS->@*);
  if ($v->error('cardTitle') || $v->error('cardText') || $v->error('cardWidth')) {
    $self->flash(error => 'Invalid submission');
    return $self->redirect_to('index');
  }
  unless (-e DASHFILE) {
    $self->flash(error => "Can't load dashboard");
    return $self->redirect_to('index');
  }
  my $cards = retrieve DASHFILE;
  my $id = time();
  $cards->{$id} = {
    id    => $id,
    title => $v->param('cardTitle'),
    text  => $v->param('cardText'),
    width => $v->param('cardWidth'),
    pos   => keys(%$cards) + 1,
  };
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub help ($self) { $self->render }

1;
