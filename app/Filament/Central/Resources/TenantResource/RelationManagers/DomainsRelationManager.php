<?php

namespace App\Filament\Central\Resources\TenantResource\RelationManagers;

use Filament\Actions\CreateAction;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Forms;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class DomainsRelationManager extends RelationManager
{
    protected static string $relationship = 'domains';

    protected static ?string $title = 'Tenant domains';

    public function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('domain')
                ->required()->maxLength(253)->unique(ignoreRecord: true)
                ->rule('regex:/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i')
                ->dehydrateStateUsing(fn (?string $state): string => strtolower(rtrim(trim((string) $state), '.')))
                ->helperText('Register only a platform-controlled and verified domain.'),
            Forms\Components\Toggle::make('is_active')
                ->label('Domain active')
                ->default(true)
                ->required(),
        ]);
    }

    public function table(Table $table): Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('domain')->searchable(),
            Tables\Columns\IconColumn::make('is_active')->boolean()->label('Active'),
            Tables\Columns\TextColumn::make('created_at')->dateTime(),
        ])->headerActions([CreateAction::make()])
            ->actions([EditAction::make(), DeleteAction::make()->requiresConfirmation()]);
    }
}
