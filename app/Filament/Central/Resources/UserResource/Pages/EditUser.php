<?php

namespace App\Filament\Central\Resources\UserResource\Pages;

use App\Filament\Central\Resources\UserResource;
use Filament\Resources\Pages\EditRecord;

class EditUser extends EditRecord
{
    protected static string $resource = UserResource::class;

    protected function mutateFormDataBeforeSave(array $data): array
    {
        if (! isset($data['password']) || trim((string) $data['password']) === '') {
            unset($data['password']);
        }

        return $data;
    }
}
