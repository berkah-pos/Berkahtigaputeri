<?php

namespace App\Filament\Central\Resources;

use App\Filament\Central\Resources\DeviceRegistryResource\Pages;
use App\Models\Central\DeviceRegistry;
use App\Models\Central\Tenant;
use App\Models\Central\User;
use Filament\Forms;
use Filament\Forms\Form;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

class DeviceRegistryResource extends Resource
{
    protected static ?string $model = DeviceRegistry::class;
    protected static ?string $navigationIcon = 'heroicon-o-device-tablet';
    protected static ?string $navigationGroup = 'Platform';
    protected static ?string $navigationLabel = 'Device Registry';
    protected static ?string $modelLabel = 'device';
    protected static ?string $pluralModelLabel = 'devices';

    public static function form(Form $form): Form
    {
        return $form->schema([
            Forms\Components\TextInput::make('device_id')
                ->required()->maxLength(150)->alphaDash()
                ->unique(ignoreRecord: true),
            Forms\Components\Select::make('tenant_id')
                ->label('Tenant')
                ->options(fn (): array => Tenant::query()->orderBy('id')->pluck('id', 'id')->all())
                ->required()->searchable(),
            Forms\Components\Select::make('owner_user_id')
                ->label('Assigned user')
                ->options(fn (): array => User::query()->where('is_active', true)->orderBy('email')->pluck('email', 'id')->all())
                ->searchable()->nullable()
                ->helperText('Optional. If set, this device can only be used by its assigned user or a central administrator.'),
            Forms\Components\Select::make('status')
                ->options(['pending' => 'Pending', 'active' => 'Active', 'suspended' => 'Suspended'])
                ->required()->default('pending'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('device_id')->searchable()->sortable(),
            Tables\Columns\TextColumn::make('tenant_id')->searchable()->sortable(),
            Tables\Columns\TextColumn::make('owner_user_id')->label('Owner user ID'),
            Tables\Columns\TextColumn::make('status')->badge()->color(fn (string $state): string => match ($state) {
                'active' => 'success',
                'suspended' => 'danger',
                default => 'gray',
            }),
            Tables\Columns\TextColumn::make('registered_at')->dateTime()->sortable(),
        ])->actions([
            Tables\Actions\EditAction::make(),
        ]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListDevices::route('/'),
            'create' => Pages\CreateDevice::route('/create'),
            'edit' => Pages\EditDevice::route('/{record}/edit'),
        ];
    }
}
