package App::GDash;
use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {

  my $config = $self->plugin('NotYAMLConfig');
  $self->plugin('DefaultHelpers');

  $self->secrets($config->{secrets});

  my $r = $self->routes;
  $r->get('/')    ->to('Main#index') ->name('index');
  $r->post('/')   ->to('Main#update')->name('update');
  $r->get('/help')->to('Main#help')  ->name('help');
}

1;
