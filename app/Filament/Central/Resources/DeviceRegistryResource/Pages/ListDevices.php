<?php

namespace App\Filament\Central\Resources\DeviceRegistryResource\Pages;

use App\Filament\Central\Resources\DeviceRegistryResource;
use Filament\Actions;
use Filament\Resources\Pages\ListRecords;

class ListDevices extends ListRecords
{
    protected static string $resource = DeviceRegistryResource::class;

    protected function getHeaderActions(): array
    {
        return [Actions\CreateAction::make()];
    }
}
