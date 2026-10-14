<?php

namespace App\Filament\Central\Resources\UserResource\Pages;

use App\Filament\Central\Resources\UserResource;
use Filament\Resources\Pages\CreateRecord;

class CreateUser extends CreateRecord
{
    protected static string $resource = UserResource::class;
}
