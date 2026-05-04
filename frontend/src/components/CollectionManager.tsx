import React, { useState, useEffect } from 'react';
import { Typography, Box, List, ListItem, ListItemText, Switch, FormControlLabel, CircularProgress } from '@mui/material';
import { useAuth } from '../context/AuthContext';

interface Game {
  id: number;
  title: string;
  generation: number;
}

interface UserGame {
  game_id: number;
  has_shiny_charm: boolean;
}

const CollectionManager: React.FC = () => {
  const { token, userId } = useAuth();
  const [games, setGames] = useState<Game[]>([]);
  const [userGames, setUserGames] = useState<UserGame[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [gamesRes, userGamesRes] = await Promise.all([
          fetch('http://localhost:8080/api/games'),
          fetch(`http://localhost:8080/api/user/${userId}/games`, {
            headers: { Authorization: `Bearer ${token}` }
          })
        ]);

        if (gamesRes.ok && userGamesRes.ok) {
          const g = await gamesRes.json();
          const ug = await userGamesRes.json() || [];
          setGames(g);
          setUserGames(ug);
        }
      } catch (err) {
        console.error("Failed to fetch collection", err);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, [token, userId]);

  const handleToggle = async (gameId: number, hasCharm: boolean) => {
    try {
      const res = await fetch(`http://localhost:8080/api/user/${userId}/games/${gameId}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({ has_shiny_charm: hasCharm })
      });

      if (res.ok) {
        setUserGames(prev => {
          const exists = prev.find(ug => ug.game_id === gameId);
          if (exists) {
            return prev.map(ug => ug.game_id === gameId ? { ...ug, has_shiny_charm: hasCharm } : ug);
          }
          return [...prev, { game_id: gameId, has_shiny_charm: hasCharm }];
        });
      }
    } catch (err) {
      console.error("Failed to update game", err);
    }
  };

  if (loading) return <CircularProgress />;

  return (
    <Box>
      <Typography variant="h4" gutterBottom>My Game Collection</Typography>
      <Typography variant="body1" color="text.secondary" paragraph>
        Select the games you own and indicate if you have the Shiny Charm.
      </Typography>
      
      <List>
        {games.map(game => {
          const ug = userGames.find(u => u.game_id === game.id);
          const isOwned = !!ug;
          const hasCharm = ug?.has_shiny_charm || false;

          return (
            <ListItem key={game.id} sx={{ bgcolor: 'background.paper', mb: 1, borderRadius: 2 }}>
              <ListItemText primary={game.title} secondary={`Generation ${game.generation}`} />
              <FormControlLabel
                control={<Switch color="secondary" checked={isOwned} onChange={(e) => {
                  if (!e.target.checked) return; // Just allow toggling on/off the charm for now
                  handleToggle(game.id, hasCharm);
                }} />}
                label="Owned"
              />
              <FormControlLabel
                control={<Switch color="primary" checked={hasCharm} disabled={!isOwned} onChange={(e) => handleToggle(game.id, e.target.checked)} />}
                label="Shiny Charm"
              />
            </ListItem>
          );
        })}
      </List>
    </Box>
  );
};

export default CollectionManager;
