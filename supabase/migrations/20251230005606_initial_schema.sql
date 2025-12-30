-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (extends Supabase auth.users)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username TEXT UNIQUE,
    display_name TEXT,
    avatar_url TEXT,
    total_score INTEGER DEFAULT 0,
    games_played INTEGER DEFAULT 0,
    games_won INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Game categories
CREATE TABLE public.categories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Questions/prompts for guessing
CREATE TABLE public.questions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    question_text TEXT NOT NULL,
    image_url TEXT,
    difficulty TEXT CHECK (difficulty IN ('easy', 'medium', 'hard')),
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Answers for each question
CREATE TABLE public.answers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
    answer_text TEXT NOT NULL,
    is_correct BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Game sessions
CREATE TABLE public.game_sessions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    host_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    game_code TEXT UNIQUE,
    status TEXT CHECK (status IN ('waiting', 'active', 'completed', 'cancelled')) DEFAULT 'waiting',
    max_players INTEGER DEFAULT 10,
    time_per_question INTEGER DEFAULT 30, -- seconds
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Players in each game session
CREATE TABLE public.game_players (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    game_session_id UUID REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    score INTEGER DEFAULT 0,
    rank INTEGER,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    UNIQUE(game_session_id, user_id)
);

-- Questions used in each game
CREATE TABLE public.game_questions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    game_session_id UUID REFERENCES game_sessions(id) ON DELETE CASCADE,
    question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
    question_order INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    UNIQUE(game_session_id, question_order)
);

-- Player responses
CREATE TABLE public.player_responses (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    game_session_id UUID REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
    answer_id UUID REFERENCES answers(id) ON DELETE CASCADE,
    response_time INTEGER, -- milliseconds
    points_earned INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Leaderboard (global)
CREATE TABLE public.leaderboard (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    period TEXT CHECK (period IN ('daily', 'weekly', 'monthly', 'all_time')),
    score INTEGER DEFAULT 0,
    rank INTEGER,
    period_start DATE,
    period_end DATE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    UNIQUE(user_id, period, period_start)
);

-- Indexes for better performance
CREATE INDEX idx_profiles_username ON profiles(username);
CREATE INDEX idx_questions_category ON questions(category_id);
CREATE INDEX idx_questions_active ON questions(is_active);
CREATE INDEX idx_answers_question ON answers(question_id);
CREATE INDEX idx_game_sessions_code ON game_sessions(game_code);
CREATE INDEX idx_game_sessions_status ON game_sessions(status);
CREATE INDEX idx_game_players_session ON game_players(game_session_id);
CREATE INDEX idx_game_players_user ON game_players(user_id);
CREATE INDEX idx_player_responses_game ON player_responses(game_session_id);
CREATE INDEX idx_player_responses_user ON player_responses(user_id);
CREATE INDEX idx_leaderboard_period ON leaderboard(period, period_start);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE leaderboard ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Profiles: Users can read all profiles, but only update their own
CREATE POLICY "Profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Categories: Everyone can read, only authenticated users can create
CREATE POLICY "Categories are viewable by everyone" ON categories FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create categories" ON categories FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Questions: Everyone can read active questions
CREATE POLICY "Active questions are viewable by everyone" ON questions FOR SELECT USING (is_active = true);
CREATE POLICY "Authenticated users can create questions" ON questions FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Answers: Everyone can read answers
CREATE POLICY "Answers are viewable by everyone" ON answers FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create answers" ON answers FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Game sessions: Everyone can read, authenticated users can create
CREATE POLICY "Game sessions are viewable by everyone" ON game_sessions FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create game sessions" ON game_sessions FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Game hosts can update their sessions" ON game_sessions FOR UPDATE USING (auth.uid() = host_id);

-- Game players: Players can read games they're in
CREATE POLICY "Users can view game players" ON game_players FOR SELECT USING (true);
CREATE POLICY "Users can join games" ON game_players FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Game questions: Everyone can read
CREATE POLICY "Game questions are viewable by everyone" ON game_questions FOR SELECT USING (true);

-- Player responses: Users can read their own responses and create new ones
CREATE POLICY "Users can view their own responses" ON player_responses FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create their own responses" ON player_responses FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Leaderboard: Everyone can read
CREATE POLICY "Leaderboard is viewable by everyone" ON leaderboard FOR SELECT USING (true);

-- Functions

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc', NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_questions_updated_at BEFORE UPDATE ON questions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, username, display_name)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on user signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Sample data (optional)
INSERT INTO categories (name, description, icon) VALUES
    ('Pop Culture', 'Movies, TV shows, and celebrities', '🎬'),
    ('History', 'Historical events and figures', '📚'),
    ('Science', 'Scientific facts and discoveries', '🔬'),
    ('Sports', 'Sports trivia and facts', '⚽'),
    ('Geography', 'Countries, cities, and landmarks', '🌍');
