const API_URL = "/api/animals"; 
let allAnimals = []; // cache dos animais

async function loadAnimals() {
  try {
    const res = await fetch(API_URL);
    const data = await res.json();

    // ✅ Corrigido: trata retorno como array OU objeto com 'animals'
    allAnimals = Array.isArray(data) ? data : (data.animals || []);
    renderAnimals(allAnimals);
  } catch (err) {
    console.error("Erro ao carregar animais:", err);
    document.getElementById("animal-list").innerHTML =
      "<p>Erro ao carregar animais.</p>";
  }
}

function renderAnimals(animals) {
  const container = document.getElementById("animal-list");
  container.innerHTML = "";

  if (!animals || animals.length === 0) {
    container.innerHTML = "<p>Nenhum animal encontrado.</p>";
    return;
  }

  animals.forEach(animal => {
    const imgUrl = animal.profile_picture_url || "https://i.ibb.co/MxRhsM0X/no-image-dog.png";

    const card = `
      <a href="animal.html?id=${animal.id}" class="animal-list-link">
        <div class="animal-strip">
          <div class="animal-photo-list-container">
            <img class="animal-photo-list" src="${imgUrl}" alt="Foto de ${animal.name}"/>
          </div>
          <div class="list-content">
            <h3>${animal.name}</h3>
            <div class="characteristics-container">
              <span class="characteristic-box">${animal.species || "-"}</span>
              <span class="characteristic-box">${animal.gender || "-"}</span>
              <span class="characteristic-box">${animal.size || "-"}</span>
              <span class="characteristic-box">${animal.age_range || "-"}</span>
            </div>
          </div>
        </div>
      </a>`;
    container.insertAdjacentHTML("beforeend", card);
  });
}

// Ativar filtros de status
function setupFilters() {
  const buttons = document.querySelectorAll(".status-filter-btn");

  buttons.forEach(btn => {
    btn.addEventListener("click", () => {
      // remover classe "active" de todos
      buttons.forEach(b => b.classList.remove("active"));
      btn.classList.add("active");

      const status = btn.dataset.status;
      if (status) {
        const filtered = allAnimals.filter(a => a.status === status);
        renderAnimals(filtered);
      } else {
        renderAnimals(allAnimals);
      }
    });
  });
}

loadAnimals().then(setupFilters);
