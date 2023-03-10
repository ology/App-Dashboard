package App::GDash::Controller::Main;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Storable qw(retrieve store);

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
      1 => {id=>1,pos=>1,width=>8,title=>'A',text=>'Foo!',refresh=>1},
      2 => {id=>2,pos=>2,width=>4,title=>'B',text=>'Bar?',refresh=>1},
      3 => {id=>3,pos=>3,width=>6,title=>'C',text=>'Baz...',refresh=>1},
      4 => {id=>4,pos=>4,width=>6,title=>'D',text=>'Derp',refresh=>1},
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
  $v->optional('showRefresh');
  if ($v->error('cardId')
    || $v->error('cardTitle')
    || $v->error('cardText')
    || $v->error('cardPosition')
    || $v->error('cardWidth')
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
  $cards->{$id}{title}   = $v->param('cardTitle');
  $cards->{$id}{text}    = $v->param('cardText');
  $cards->{$id}{width}   = $v->param('cardWidth');
  $cards->{$id}{refresh} = $v->param('showRefresh') ? 1 : 0;

  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub swap ($self) {
  my $v = $self->validation;
  $v->required('x')->like(qr/^\d+$/);
  $v->required('y')->like(qr/^\d+$/);
  if ($v->error('x') || $v->error('y')) {
    return $self->render(json => {}, status => 400);
  }
  unless (-e DASHFILE) {
    return $self->render(json => {}, status => 400);
  }
  my $cards = retrieve DASHFILE;
  my $x = $v->param('x');
  my $y = $v->param('y');
  my $x_pos = $cards->{$x}{pos};
  $cards->{$x}{pos} = $cards->{$y}{pos};
  $cards->{$y}{pos} = $x_pos;
  store($cards, DASHFILE);
  $self->render(json => {}, status => 200);
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
    my $content = rss_cmd($1);
    $cards->{$id}{content} = $content;
  }
  elsif ($cards->{$id}{text} =~ /^perl:(.+)$/) {
    my $content = perl_cmd($1);
    $cards->{$id}{content} = $content;
  }
  elsif ($cards->{$id}{text} =~ /^curl:(.+)$/) {
    my $content = curl_cmd($1);
    $cards->{$id}{content} = $content;
  }
  else {
    delete $cards->{$id}{content} if exists $cards->{$id}{content};
  }
  store($cards, DASHFILE);
  $self->render(text => ($cards->{$id}{content} || $cards->{$id}{text}))
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
  $v->optional('showRefresh');
  if ($v->error('cardTitle')
    || $v->error('cardText')
    || $v->error('cardWidth')
) {
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
    id      => $id,
    title   => $v->param('cardTitle'),
    text    => $v->param('cardText'),
    width   => $v->param('cardWidth'),
    pos     => keys(%$cards) + 1,
    refresh => $v->param('showRefresh') ? 1 : 0,
  };
  store($cards, DASHFILE);
  $self->redirect_to('index');
}

sub help ($self) { $self->render }

1;
