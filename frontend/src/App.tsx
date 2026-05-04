import { useState } from 'react';
import { Box, AppBar, Toolbar, Typography, Container, Tabs, Tab, Button } from '@mui/material';
import CatchingPokemonIcon from '@mui/icons-material/CatchingPokemon';
import AddIcon from '@mui/icons-material/Add';
import Dashboard from './components/Dashboard';
import CollectionManager from './components/CollectionManager';
import NewHuntModal from './components/NewHuntModal';
import Login from './components/Login';
import { useAuth } from './context/AuthContext';

function App() {
  const { token, logout } = useAuth();
  const [tabIndex, setTabIndex] = useState(0);
  const [modalOpen, setModalOpen] = useState(false);

  if (!token) {
    return (
      <Box sx={{ flexGrow: 1, minHeight: '100vh', bgcolor: 'background.default' }}>
        <AppBar position="static" elevation={0} sx={{ bgcolor: 'background.paper', borderBottom: 1, borderColor: 'divider' }}>
          <Toolbar>
            <CatchingPokemonIcon sx={{ mr: 2, color: 'primary.main' }} />
            <Typography variant="h6" component="div" sx={{ flexGrow: 1, fontWeight: 700 }}>
              ShinyTracker
            </Typography>
          </Toolbar>
        </AppBar>
        <Login />
      </Box>
    );
  }

  return (
    <Box sx={{ flexGrow: 1, minHeight: '100vh', bgcolor: 'background.default' }}>
      <AppBar position="static" elevation={0} sx={{ bgcolor: 'background.paper', borderBottom: 1, borderColor: 'divider' }}>
        <Toolbar>
          <CatchingPokemonIcon sx={{ mr: 2, color: 'primary.main' }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1, fontWeight: 700 }}>
            ShinyTracker
          </Typography>
          <Button 
            variant="contained" 
            color="primary" 
            startIcon={<AddIcon />}
            onClick={() => setModalOpen(true)}
            sx={{ mr: 2 }}
          >
            New Hunt
          </Button>
          <Button color="inherit" onClick={logout}>Logout</Button>
        </Toolbar>
      </AppBar>

      <Container maxWidth="lg" sx={{ mt: 4 }}>
        <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}>
          <Tabs value={tabIndex} onChange={(_, newValue) => setTabIndex(newValue)} textColor="primary" indicatorColor="primary">
            <Tab label="Dashboard" />
            <Tab label="Collection Manager" />
          </Tabs>
        </Box>

        {tabIndex === 0 && <Dashboard />}
        {tabIndex === 1 && <CollectionManager />}
      </Container>

      <NewHuntModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </Box>
  );
}

export default App;
