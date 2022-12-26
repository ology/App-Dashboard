use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('App::GDash');

$t->ua->max_redirects(1);

$t->get_ok($t->app->url_for('index'))
  ->status_is(200)
  ->content_like(qr/Thing:/)
  ->element_exists('label[for=thing]')
  ->element_exists('input[name=thing][type=text]')
  ->element_exists('input[type=submit]');
;

$t->post_ok($t->app->url_for('index'), form => { thing => 'xyz' })
  ->status_is(200)
  ->element_exists('input[name=thing][type=text][value=xyz]')
;

$t->post_ok($t->app->url_for('index'), form => { thing => 'x' x 99 })
  ->status_is(200)
  ->content_like(qr/Invalid thing/)
;

$t->get_ok($t->app->url_for('help'))
  ->status_is(200)
;

done_testing();
