<?php

namespace App\\Providers\\Filament;

use Filament\\Http\\Middleware\\Authenticate;
use Filament\\Http\\Middleware\\AuthenticateSession;
use Filament\\Http\\Middleware\\DispatchServingFilamentEvent;
use Filament\\Pages;
use Filament\\Panel;
use Filament\\PanelProvider;
use Filament\\Support\\Colors\\Color;
use Illuminate\\Cookie\\Middleware\\AddQueuedCookiesToResponse;
use Illuminate\\Cookie\\Middleware\\EncryptCookies;
use Illuminate\\Foundation\\Http\\Middleware\\VerifyCsrfToken;
use Illuminate\\Routing\\Middleware\\SubstituteBindings;
use Illuminate\\Session\\Middleware\\StartSession;
use Illuminate\\View\\Middleware\\ShareErrorsFromSession;

class CentralPanelProvider extends PanelProvider
{
    public function panel(Panel $panel): Panel
    {
        return $panel
            ->default()
            ->id('central')
            ->path('central/admin')
            ->login()
            ->colors(['primary' => Color::Emerald])
            ->discoverResources(in: app_path('Filament/Central/Resources'), for: 'App\\Filament\\Central\\Resources')
            ->discoverPages(in: app_path('Filament/Central/Pages'), for: 'App\\Filament\\Central\\Pages')
            ->pages([Pages\\Dashboard::class])
            ->middleware([
                EncryptCookies::class,
                AddQueuedCookiesToResponse::class,
                StartSession::class,
                AuthenticateSession::class,
                ShareErrorsFromSession::class,
                VerifyCsrfToken::class,
                SubstituteBindings::class,
                DispatchServingFilamentEvent::class,
            ])
            ->authMiddleware([Authenticate::class]);
    }
}
