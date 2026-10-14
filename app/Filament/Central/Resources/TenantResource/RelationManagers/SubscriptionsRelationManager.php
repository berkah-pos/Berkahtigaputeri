<?php

namespace App\Filament\Central\Resources\TenantResource\RelationManagers;

use Filament\Forms;
use Filament\Forms\Form;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables;
use Filament\Tables\Table;

class SubscriptionsRelationManager extends RelationManager
{
    protected static string $relationship = 'subscriptions';
    protected static ?string $title = 'Subscriptions';

    public function form(Form $form): Form
    {
        return $form->schema([
            Forms\Components\Select::make('plan')
                ->options(['trial' => 'Trial', 'basic' => 'Basic', 'pro' => 'Pro', 'enterprise' => 'Enterprise'])
                ->required(),
            Forms\Components\Select::make('status')
                ->options(['trial' => 'Trial', 'active' => 'Active', 'suspended' => 'Suspended', 'cancelled' => 'Cancelled'])
                ->required(),
            Forms\Components\DateTimePicker::make('expires_at'),
            Forms\Components\TextInput::make('provider_reference')->maxLength(255),
        ]);
    }

    public function table(Table $table): Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('plan')->badge(),
            Tables\Columns\TextColumn::make('status')->badge(),
            Tables\Columns\TextColumn::make('expires_at')->dateTime()->sortable(),
            Tables\Columns\TextColumn::make('created_at')->dateTime(),
        ])->headerActions([Tables\Actions\CreateAction::make()])
          ->actions([
              Tables\Actions\EditAction::make(),
              Tables\Actions\DeleteAction::make()->requiresConfirmation(),
          ]);
    }
}
