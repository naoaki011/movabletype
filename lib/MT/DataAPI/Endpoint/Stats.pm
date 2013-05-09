package MT::DataAPI::Endpoint::Stats;

use strict;
use warnings;

use URI;
use MT::Stats;
use MT::DataAPI::Resource;

sub _invoke {
    my ( $app, $endpoint ) = @_;

    ( my $method = ( caller 1 )[3] ) =~ s/.*:://;

    my $provider = readied_provider( $app, $app->blog )
        or return $app->error( 'Readied provider is not found', 404 );

    my $params = {
        startDate => scalar( $app->param('startDate') ),
        endDate   => scalar( $app->param('endDate') ),
        limit     => scalar( $app->param('limit') ),
    };
    $params->{path} = do {
        if ( defined( my $path = $app->param('path') ) ) {
            $path;
        }
        else {
            URI->new( $app->blog->site_url )->path;
        }
    };

    $provider->$method( $app, $params );
}

sub pageviews_for_path {
    my ( $app, $endpoint ) = @_;
    _maybe_raw( fill_in_archive_info( _invoke(@_), $app->blog ) );
}

sub visits_for_path {
    my ( $app, $endpoint ) = @_;
    _maybe_raw( fill_in_archive_info( _invoke(@_), $app->blog ) );
}

sub pageviews_for_date {
    _maybe_raw( _invoke(@_) );
}

sub visits_for_date {
    _maybe_raw( _invoke(@_) );
}

sub _maybe_raw {
    $_[0] ? MT::DataAPI::Resource::Type::Raw->new( $_[0] ) : ();
}

sub fill_in_archive_info {
    my ( $data, $blog ) = @_;

    return unless $data;

    my %items = ();
    my ( @in_paths, @like_paths );

    foreach my $i ( @{ $data->{items} } ) {
        my $path = $i->{path};
        $items{$path} = $i;

        if ( $path =~ m#/\z# ) {
            $path =~ s{/\z}{/index.%};
            push @like_paths, '-or' if @like_paths;
            push @like_paths, { url => { like => $path } };
        }
        else {
            push @in_paths, $path;
        }

        for my $k (qw(archiveType entry category author)) {
            $i->{$k} = undef;
        }
    }

    return $data if !@in_paths && !@like_paths;

    my $iter = MT->model('fileinfo')->load_iter(
        [   { blog_id => $blog->id, },
            '-and',
            [   ( @in_paths ? ( { url => \@in_paths, }, ) : () ),
                ( @in_paths && @like_paths ? '-or' : () ),
                @like_paths,
            ]
        ]
    );

    while ( my $fi = $iter->() ) {
        my $url = $fi->url;
        my $i   = $items{$url};
        if ( !$i ) {
            $url =~ s#\/index\.[^/]+\z#/#g;
            $i = $items{$url};
        }
        next unless $i;

        $i->{archiveType} = $fi->archive_type if defined $fi->archive_type;
        for my $k (qw(entry_id category_id author_id)) {
            if ( defined $fi->$k ) {
                ( my $hk = $k ) =~ s/_.*//g;
                $i->{$hk} = { id => $fi->$k, };
            }
        }
        ( $i->{startDate} = $fi->startdate )
            =~ s/(\d{4})(\d{2})(\d{2}).*/$1-$2-$3/
            if defined $fi->startdate;
    }

    $data;
}

1;